import Combine
import Foundation

@MainActor
final class FFmpegPathsStore: ObservableObject {
    @Published var ffmpegPath: String {
        didSet { UserDefaults.standard.set(ffmpegPath, forKey: Self.ffmpegPathKey) }
    }

    @Published var ffprobePath: String {
        didSet { UserDefaults.standard.set(ffprobePath, forKey: Self.ffprobePathKey) }
    }

    private static let ffmpegPathKey = "ffmpegPath"
    private static let ffprobePathKey = "ffprobePath"

    init() {
        ffmpegPath = UserDefaults.standard.string(forKey: Self.ffmpegPathKey) ?? BinaryResolver.find("ffmpeg") ?? ""
        ffprobePath = UserDefaults.standard.string(forKey: Self.ffprobePathKey) ?? BinaryResolver.find("ffprobe") ?? ""
    }

    var isConfigured: Bool {
        FileManager.default.isExecutableFile(atPath: ffmpegPath) &&
            FileManager.default.isExecutableFile(atPath: ffprobePath)
    }
}

enum BinaryResolver {
    static func find(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
