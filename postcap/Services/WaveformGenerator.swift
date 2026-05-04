import Foundation

struct WaveformGenerator {
    var ffmpegPath: String
    var colorHex: String

    func generateWaveform(inputURL: URL, track: AudioTrack, width: Int = 1400) async throws -> WaveformImage {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("postcap-waveform-\(UUID().uuidString)-track-\(track.index).png")

        let output = try await ProcessRunner.run(
            executablePath: ffmpegPath,
            arguments: [
                "-hide_banner",
                "-i", inputURL.path,
                "-filter_complex", "[0:a:\(track.index)]showwavespic=s=\(width)x120:colors=\(sanitizedColorHex)",
                "-frames:v", "1",
                "-c:v", "png",
                "-y",
                outputURL.path
            ]
        )

        guard output.exitCode == 0 else {
            throw FFmpegExporterError.failed(output.exitCode, output.stderr)
        }

        return WaveformImage(trackIndex: track.index, imageURL: outputURL)
    }

    private var sanitizedColorHex: String {
        let allowed = Set("0123456789abcdefABCDEF")
        let filtered = colorHex.filter { allowed.contains($0) }
        return filtered.isEmpty ? "FFFFFF" : String(filtered.prefix(6))
    }
}
