import Foundation

enum VideoAnalyzerError: LocalizedError {
    case noVideoStream
    case ffprobeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoStream:
            "No video stream was found in this file."
        case .ffprobeFailed(let message):
            "ffprobe failed: \(message)"
        }
    }
}

struct VideoAnalyzer {
    var ffprobePath: String

    func getVideoInfo(fileURL: URL) async throws -> VideoInfo {
        let output = try await ProcessRunner.run(
            executablePath: ffprobePath,
            arguments: [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                fileURL.path
            ]
        )

        guard output.exitCode == 0 else {
            throw VideoAnalyzerError.ffprobeFailed(output.stderr)
        }

        let data = Data(output.stdout.utf8)
        let response = try JSONDecoder().decode(FFprobeResponse.self, from: data)
        return try parseVideoInfo(response)
    }

    private func parseVideoInfo(_ response: FFprobeResponse) throws -> VideoInfo {
        guard let videoStream = response.streams.first(where: { $0.codecType == "video" }) else {
            throw VideoAnalyzerError.noVideoStream
        }

        let audioStreams = response.streams.filter { $0.codecType == "audio" }
        let audioTracks = audioStreams.enumerated().map { index, stream in
            AudioTrack(
                index: index,
                codec: stream.codecName ?? "unknown",
                channels: stream.channels ?? 0,
                sampleRate: Int(stream.sampleRate ?? "") ?? 0,
                bitrate: stream.bitRate ?? "0",
                language: stream.tags?.language
            )
        }

        return VideoInfo(
            duration: Double(response.format.duration ?? "") ?? 0,
            width: videoStream.width ?? 0,
            height: videoStream.height ?? 0,
            fps: parseFps(videoStream.rFrameRate),
            bitrate: response.format.bitRate ?? "0",
            audioTracks: audioTracks,
            videoCodec: videoStream.codecName ?? "unknown",
            audioCodec: audioStreams.first?.codecName ?? "none",
            format: response.format.formatName ?? "unknown"
        )
    }

    private func parseFps(_ frameRate: String?) -> Double {
        guard let frameRate, !frameRate.isEmpty else { return 0 }
        let parts = frameRate.split(separator: "/").compactMap { Double($0) }
        if parts.count == 2, parts[1] != 0 {
            return (parts[0] / parts[1] * 100).rounded() / 100
        }
        return parts.first ?? 0
    }
}

private struct FFprobeResponse: Decodable {
    var streams: [FFprobeStream]
    var format: FFprobeFormat
}

private struct FFprobeStream: Decodable {
    var codecName: String?
    var codecType: String?
    var width: Int?
    var height: Int?
    var rFrameRate: String?
    var channels: Int?
    var sampleRate: String?
    var bitRate: String?
    var tags: FFprobeTags?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecType = "codec_type"
        case width
        case height
        case rFrameRate = "r_frame_rate"
        case channels
        case sampleRate = "sample_rate"
        case bitRate = "bit_rate"
        case tags
    }
}

private struct FFprobeFormat: Decodable {
    var duration: String?
    var bitRate: String?
    var formatName: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case bitRate = "bit_rate"
        case formatName = "format_name"
    }
}

private struct FFprobeTags: Decodable {
    var language: String?
}
