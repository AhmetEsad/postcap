import Combine
import Foundation

enum FFmpegExporterError: LocalizedError {
    case unsupportedEncoder(String)
    case invalidTrim
    case failed(Int32, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoder(let encoder):
            "Unsupported encoder: \(encoder)."
        case .invalidTrim:
            "Trim end time must be greater than trim start time."
        case .failed(let code, let message):
            "ffmpeg failed with exit code \(code): \(message)"
        case .cancelled:
            "Export cancelled."
        }
    }
}

@MainActor
final class FFmpegExporter: ObservableObject {
    @Published private(set) var isExporting = false
    @Published var progress = ExportProgress()

    private var process: Process?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    func availableEncoders(ffmpegPath: String) async -> Set<VideoEncoder> {
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else { return [] }
        do {
            let output = try await ProcessRunner.run(executablePath: ffmpegPath, arguments: ["-hide_banner", "-encoders"])
            return Set(VideoEncoder.allCases.filter { output.stdout.contains($0.rawValue) || output.stderr.contains($0.rawValue) })
        } catch {
            return []
        }
    }

    func export(_ request: ExportRequest, ffmpegPath: String) async throws {
        guard VideoEncoder.allCases.contains(request.encoder) else {
            throw FFmpegExporterError.unsupportedEncoder(request.encoder.rawValue)
        }

        let arguments = try buildArguments(for: request)
        progress = ExportProgress(status: "Preparing export")
        isExporting = true
        defer {
            isExporting = false
            process = nil
            stdoutBuffer = ""
            stderrBuffer = ""
        }

        try await runFFmpeg(ffmpegPath: ffmpegPath, arguments: arguments, duration: exportDuration(for: request))
    }

    func cancel() {
        mutateProgress { $0.status = "Cancelling" }
        process?.terminate()
    }

    func buildArguments(for request: ExportRequest) throws -> [String] {
        if request.trim.enabled, request.trim.end > 0, request.trim.end <= request.trim.start {
            throw FFmpegExporterError.invalidTrim
        }

        var arguments: [String] = ["-hide_banner", "-nostdin"]

        if request.trim.enabled, request.trim.start > 0 {
            arguments += ["-ss", formatSeconds(request.trim.start)]
        }

        arguments += ["-i", request.inputURL.path]

        if request.trim.enabled, request.trim.end > 0 {
            if request.trim.start > 0 {
                arguments += ["-t", formatSeconds(request.trim.end - request.trim.start)]
            } else {
                arguments += ["-to", formatSeconds(request.trim.end)]
            }
        }

        if request.crop.enabled {
            arguments += ["-vf", "crop=\(request.crop.width):\(request.crop.height):\(request.crop.x):\(request.crop.y)"]
        }

        arguments += ["-map", "0:v:0", "-c:v", request.encoder.rawValue]

        let trimmedBitrate = request.bitrate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBitrate.isEmpty {
            arguments += ["-b:v", trimmedBitrate]
        }

        appendAudioArguments(to: &arguments, request: request)

        arguments += [
            "-stats_period", "0.25",
            "-progress", "pipe:1",
            "-nostats",
            "-y",
            request.outputURL.path
        ]

        return arguments
    }

    private func appendAudioArguments(to arguments: inout [String], request: ExportRequest) {
        let keptTracks = request.videoInfo.audioTracks.filter {
            request.audioSettings[$0.index, default: AudioTrackSettings()].isIncluded
        }

        guard !keptTracks.isEmpty else {
            arguments.append("-an")
            return
        }

        let hasVolumeChanges = keptTracks.contains {
            abs(request.audioSettings[$0.index, default: AudioTrackSettings()].volume - 1) > 0.001
        }

        if hasVolumeChanges {
            let filters = keptTracks.map { track in
                let volume = request.audioSettings[track.index, default: AudioTrackSettings()].volume
                return "[0:a:\(track.index)]volume=\(formatVolume(volume))[a\(track.index)]"
            }
            arguments += ["-filter_complex", filters.joined(separator: ";")]
            keptTracks.forEach { arguments += ["-map", "[a\($0.index)]"] }
            arguments += ["-c:a", "aac"]
        } else {
            keptTracks.forEach { arguments += ["-map", "0:a:\($0.index)?"] }
            arguments += ["-c:a", "copy"]
        }
    }

    private func runFFmpeg(ffmpegPath: String, arguments: [String], duration: Double) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            self.process = process

            final class ProcessCapture: @unchecked Sendable {
                private let lock = NSLock()
                private var stderrText = ""
                private var didResume = false

                func appendStderr(_ text: String) {
                    lock.lock()
                    stderrText += text
                    lock.unlock()
                }

                func stderr() -> String {
                    lock.lock()
                    defer { lock.unlock() }
                    return stderrText
                }

                func claimResume() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return false }
                    didResume = true
                    return true
                }
            }

            let capture = ProcessCapture()
            let exporter = self

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    exporter.consumeProgressChunk(text, duration: duration)
                }
            }

            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                capture.appendStderr(text)
                Task { @MainActor in
                    exporter.consumeStderrChunk(text, duration: duration)
                }
            }

            process.terminationHandler = { terminatedProcess in
                guard capture.claimResume() else { return }
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil

                let status = terminatedProcess.terminationStatus
                Task { @MainActor in
                    self.consumeProgressChunk(String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "", duration: duration)
                    self.consumeStderrChunk(String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "", duration: duration)

                    if status == 0 {
                        self.mutateProgress {
                            $0.fraction = 1
                            $0.status = "Complete"
                        }
                        continuation.resume()
                    } else if terminatedProcess.terminationReason == .uncaughtSignal {
                        self.mutateProgress { $0.status = "Cancelled" }
                        continuation.resume(throwing: FFmpegExporterError.cancelled)
                    } else {
                        self.mutateProgress { $0.status = "Failed" }
                        continuation.resume(throwing: FFmpegExporterError.failed(status, capture.stderr()))
                    }
                }
            }

            do {
                mutateProgress { $0.status = "Exporting" }
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func consumeProgressChunk(_ text: String, duration: Double) {
        stdoutBuffer += text
        let lines = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        stdoutBuffer = lines.last ?? ""
        lines.dropLast().forEach { consumeProgressLine($0, duration: duration) }
    }

    private func consumeProgressLine(_ line: String, duration: Double) {
        mutateProgress { $0.appendLog(line) }
        let pieces = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return }
        applyProgressKey(pieces[0], value: pieces[1], duration: duration)
    }

    private func consumeStderrChunk(_ text: String, duration: Double) {
        stderrBuffer += text.replacingOccurrences(of: "\r", with: "\n")
        let lines = stderrBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        stderrBuffer = lines.last ?? ""
        lines.dropLast().forEach { consumeStderrLine($0, duration: duration) }
    }

    private func consumeStderrLine(_ rawLine: String, duration: Double) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        mutateProgress { $0.appendLog(line) }
        guard let seconds = parseStderrTime(line) else { return }
        mutateProgress {
            $0.currentSeconds = seconds
            if duration > 0 {
                $0.fraction = min(max(seconds / duration, 0), 1)
            }
        }
    }

    private func parseStderrTime(_ line: String) -> Double? {
        guard let range = line.range(of: #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression) else {
            return nil
        }

        let timeString = String(line[range]).replacingOccurrences(of: "time=", with: "")
        let pieces = timeString.split(separator: ":").compactMap { Double($0) }
        guard pieces.count == 3 else { return nil }
        return pieces[0] * 3600 + pieces[1] * 60 + pieces[2]
    }

    private func applyProgressKey(_ key: String, value: String, duration: Double) {
        switch key {
        case "out_time_ms":
            let seconds = (Double(value) ?? 0) / 1_000_000
            mutateProgress {
                $0.currentSeconds = seconds
                if duration > 0 {
                    $0.fraction = min(max(seconds / duration, 0), 1)
                }
            }
        case "out_time_us":
            let seconds = (Double(value) ?? 0) / 1_000_000
            mutateProgress {
                $0.currentSeconds = seconds
                if duration > 0 {
                    $0.fraction = min(max(seconds / duration, 0), 1)
                }
            }
        case "out_time":
            if let seconds = parseProgressTime(value) {
                mutateProgress {
                    $0.currentSeconds = seconds
                    if duration > 0 {
                        $0.fraction = min(max(seconds / duration, 0), 1)
                    }
                }
            }
        case "frame":
            mutateProgress { $0.frame = Int(value) ?? $0.frame }
        case "speed":
            mutateProgress { $0.speed = value }
        case "progress":
            mutateProgress { $0.status = value == "end" ? "Finalizing" : "Exporting" }
        default:
            break
        }
    }

    private func mutateProgress(_ update: (inout ExportProgress) -> Void) {
        var next = progress
        update(&next)
        progress = next
    }

    private func parseProgressTime(_ value: String) -> Double? {
        let pieces = value.split(separator: ":").compactMap { Double($0) }
        guard pieces.count == 3 else { return nil }
        return pieces[0] * 3600 + pieces[1] * 60 + pieces[2]
    }

    private func exportDuration(for request: ExportRequest) -> Double {
        guard request.trim.enabled else { return request.videoInfo.duration }
        if request.trim.end > request.trim.start {
            return request.trim.end - request.trim.start
        }
        return max(request.videoInfo.duration - request.trim.start, 0)
    }

    private func formatSeconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func formatVolume(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
