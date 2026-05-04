import Foundation

struct VideoInfo: Equatable {
    var duration: Double
    var width: Int
    var height: Int
    var fps: Double
    var bitrate: String
    var audioTracks: [AudioTrack]
    var videoCodec: String
    var audioCodec: String
    var format: String
}

struct AudioTrack: Identifiable, Equatable {
    var id: Int { index }
    var index: Int
    var codec: String
    var channels: Int
    var sampleRate: Int
    var bitrate: String
    var language: String?
}

struct CropSettings: Equatable {
    var x: Int = 0
    var y: Int = 0
    var width: Int = 0
    var height: Int = 0
    var enabled: Bool = false
}

struct TrimSettings: Equatable {
    var start: Double = 0
    var end: Double = 0
    var enabled: Bool = false
}

enum VideoEncoder: String, CaseIterable, Identifiable {
    case h264VideoToolbox = "h264_videotoolbox"
    case hevcVideoToolbox = "hevc_videotoolbox"
    case libx264 = "libx264"
    case libx265 = "libx265"
    case proRes = "prores_ks"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264VideoToolbox:
            "H.264 VideoToolbox (Hardware)"
        case .hevcVideoToolbox:
            "H.265 VideoToolbox (Hardware)"
        case .libx264:
            "H.264 libx264 (Software)"
        case .libx265:
            "H.265 libx265 (Software)"
        case .proRes:
            "ProRes"
        }
    }

    var isHardwareAccelerated: Bool {
        switch self {
        case .h264VideoToolbox, .hevcVideoToolbox:
            true
        case .libx264, .libx265, .proRes:
            false
        }
    }
}

struct AudioTrackSettings: Equatable {
    var isIncluded: Bool = true
    var volume: Double = 1
}

struct ExportRequest: Equatable {
    var inputURL: URL
    var outputURL: URL
    var videoInfo: VideoInfo
    var encoder: VideoEncoder
    var bitrate: String
    var crop: CropSettings
    var trim: TrimSettings
    var audioSettings: [Int: AudioTrackSettings]
}

struct WaveformImage: Identifiable, Equatable {
    var id: Int { trackIndex }
    var trackIndex: Int
    var imageURL: URL
}

struct ExportProgress: Equatable {
    var fraction: Double = 0
    var currentSeconds: Double = 0
    var speed: String = ""
    var frame: Int = 0
    var status: String = "Idle"
    var logLines: [String] = []

    mutating func appendLog(_ line: String) {
        guard !line.isEmpty else { return }
        logLines.append(line)
        if logLines.count > 120 {
            logLines.removeFirst(logLines.count - 120)
        }
    }
}
