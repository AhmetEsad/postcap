import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var inputURL: URL?
    @Published var outputURL: URL?
    @Published var player: AVPlayer?
    @Published var videoInfo: VideoInfo?
    @Published var crop = CropSettings()
    @Published var trim = TrimSettings()
    @Published var audioSettings: [Int: AudioTrackSettings] = [:]
    @Published var encoder: VideoEncoder = .h264VideoToolbox
    @Published var bitrate = ""
    @Published var errorMessage: String?
    @Published var availableEncoders: Set<VideoEncoder> = []
    @Published var isAnalyzing = false
    @Published var isGeneratingWaveforms = false
    @Published var waveforms: [Int: WaveformImage] = [:]
    @Published var waveformRenderWidth = 900
    @Published var exportCompletionMessage: String?
    @Published var playbackSeconds: Double = 0
    @Published var isPlaying = false

    @AppStorage("autoGenerateWaveforms") var autoGenerateWaveforms = true
    @AppStorage("autoGenerateWaveformsUnderMinutes") var autoGenerateWaveformsUnderMinutes = 3
    @AppStorage("waveformColorHex") var waveformColorHex = "FFFFFF"
    @AppStorage("openDestinationFolderAfterExport") var openDestinationFolderAfterExport = false

    let pathsStore = FFmpegPathsStore()
    let exporter = FFmpegExporter()
    private var playbackTimeObserver: Any?
    private weak var observedPlayer: AVPlayer?

    var canExport: Bool {
        inputURL != nil && videoInfo != nil && outputURL != nil && pathsStore.isConfigured && !exporter.isExporting
    }

    func refreshEncoders() {
        Task {
            availableEncoders = await exporter.availableEncoders(ffmpegPath: pathsStore.ffmpegPath)
        }
    }

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importVideo(url) }
    }

    func importVideo(_ url: URL) async {
        guard pathsStore.isConfigured else {
            errorMessage = "Choose valid ffmpeg and ffprobe binaries first."
            return
        }

        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        do {
            let info = try await VideoAnalyzer(ffprobePath: pathsStore.ffprobePath).getVideoInfo(fileURL: url)
            inputURL = url
            player = AVPlayer(url: url)
            installPlaybackObserver()
            videoInfo = info
            outputURL = defaultOutputURL(for: url, encoder: encoder)
            crop = CropSettings(x: 0, y: 0, width: info.width, height: info.height, enabled: false)
            trim = TrimSettings(start: 0, end: info.duration, enabled: false)
            audioSettings = Dictionary(uniqueKeysWithValues: info.audioTracks.map { ($0.index, AudioTrackSettings()) })
            waveforms = [:]
            playbackSeconds = 0
            isPlaying = false
            generateWaveformsIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = outputURL?.lastPathComponent ?? "postcap-export.mp4"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
    }

    func chooseBinary(kind: BinaryKind) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch kind {
        case .ffmpeg:
            pathsStore.ffmpegPath = url.path
        case .ffprobe:
            pathsStore.ffprobePath = url.path
        }
        refreshEncoders()
    }

    func export() {
        guard let inputURL, let outputURL, let videoInfo else { return }

        let request = ExportRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            videoInfo: videoInfo,
            encoder: encoder,
            bitrate: bitrate,
            crop: crop,
            trim: trim,
            audioSettings: audioSettings
        )

        Task {
            do {
                errorMessage = nil
                try await exporter.export(request, ffmpegPath: pathsStore.ffmpegPath)
                exportCompletionMessage = "Export finished: \(outputURL.lastPathComponent)"
                if openDestinationFolderAfterExport {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            } catch FFmpegExporterError.cancelled {
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.video.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = Self.url(fromDroppedItem: item) else { return }
                Task { @MainActor in
                    await self.importVideo(url)
                }
            }
            return true
        }

        let typeIdentifier = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie.identifier : UTType.video.identifier
        provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, _ in
            guard let url else { return }
            Task { @MainActor in
                await self.importVideo(url)
            }
        }

        return true
    }

    private static func url(fromDroppedItem item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let url = item as? URL {
            return url
        }

        if let string = item as? String {
            return URL(string: string) ?? URL(fileURLWithPath: string)
        }

        return nil
    }

    func updateTimelineWaveformWidth(_ width: Double) {
        let measuredWidth = max(Int(width.rounded()), 320)
        if abs(measuredWidth - waveformRenderWidth) > 16 {
            waveformRenderWidth = measuredWidth
        }
    }

    func generateWaveformsIfNeeded() {
        guard let videoInfo, waveforms.isEmpty, shouldAutoGenerateWaveforms(for: videoInfo) else { return }
        generateWaveforms()
    }

    func generateWaveforms(width: Int? = nil) {
        guard let inputURL, let videoInfo, !videoInfo.audioTracks.isEmpty, pathsStore.isConfigured, !isGeneratingWaveforms else { return }

        isGeneratingWaveforms = true
        let renderWidth = max(width ?? waveformRenderWidth, 320)
        Task {
            defer { isGeneratingWaveforms = false }
            let generator = WaveformGenerator(ffmpegPath: pathsStore.ffmpegPath, colorHex: waveformColorHex)

            for track in videoInfo.audioTracks {
                do {
                    let waveform = try await generator.generateWaveform(inputURL: inputURL, track: track, width: renderWidth)
                    waveforms[track.index] = waveform
                } catch {
                    exporter.progress.appendLog("Waveform track \(track.index + 1) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func seek(to seconds: Double) {
        let clampedSeconds = min(max(seconds, 0), videoInfo?.duration ?? seconds)
        playbackSeconds = clampedSeconds
        player?.seek(to: CMTime(seconds: clampedSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        guard let player else { return }
        if player.rate == 0 {
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func skipPlayback(by delta: Double) {
        seek(to: playbackSeconds + delta)
    }

    private func installPlaybackObserver() {
        if let playbackTimeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(playbackTimeObserver)
            self.playbackTimeObserver = nil
        }

        guard let player else { return }
        observedPlayer = player
        playbackTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self, weak player] time in
            Task { @MainActor [weak self, weak player] in
                guard let self else { return }
                playbackSeconds = time.seconds.isFinite ? time.seconds : 0
                isPlaying = player?.rate != 0
            }
        }
    }

    func applyCropPreset(_ preset: CropPreset) {
        guard let videoInfo else { return }
        crop.enabled = true

        switch preset {
        case .full:
            crop = CropSettings(x: 0, y: 0, width: videoInfo.width, height: videoInfo.height, enabled: true)
        case .centerSquare:
            let side = min(videoInfo.width, videoInfo.height)
            crop = CropSettings(x: (videoInfo.width - side) / 2, y: (videoInfo.height - side) / 2, width: side, height: side, enabled: true)
        case .centerPortrait:
            let height = videoInfo.height
            let width = min(videoInfo.width, Int(Double(height) * 9 / 16))
            crop = CropSettings(x: (videoInfo.width - width) / 2, y: 0, width: width, height: height, enabled: true)
        case .centerLandscape:
            let width = videoInfo.width
            let height = min(videoInfo.height, Int(Double(width) * 9 / 16))
            crop = CropSettings(x: 0, y: (videoInfo.height - height) / 2, width: width, height: height, enabled: true)
        }
    }

    private func shouldAutoGenerateWaveforms(for info: VideoInfo) -> Bool {
        autoGenerateWaveforms && info.duration <= Double(max(autoGenerateWaveformsUnderMinutes, 1) * 60)
    }

    private func defaultOutputURL(for input: URL, encoder: VideoEncoder) -> URL {
        let suffix: String
        switch encoder {
        case .hevcVideoToolbox, .libx265:
            suffix = "hevc"
        case .proRes:
            suffix = "prores"
        case .h264VideoToolbox, .libx264:
            suffix = "h264"
        }
        return input.deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)-postcap-\(suffix).mp4")
    }
}

enum BinaryKind {
    case ffmpeg
    case ffprobe
}

enum CropPreset: String, CaseIterable, Identifiable {
    case full = "Full"
    case centerLandscape = "16:9"
    case centerPortrait = "9:16"
    case centerSquare = "1:1"

    var id: String { rawValue }
}
