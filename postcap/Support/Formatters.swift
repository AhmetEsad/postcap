import Foundation

enum Formatters {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func bitrate(_ value: String) -> String {
        guard let bits = Double(value), bits > 0 else { return "Unknown" }
        return String(format: "%.1f Mbps", bits / 1_000_000)
    }

    static func sampleRate(_ value: Int) -> String {
        guard value > 0 else { return "Unknown" }
        return String(format: "%.1f kHz", Double(value) / 1000)
    }
}
