import AppKit
import Foundation

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let defaultsKey = "hapticFeedbackEnabled"

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    func exportCompleted() {
        guard isEnabled else { return }

        Task { @MainActor in
            perform(.alignment)
            try? await Task.sleep(for: .milliseconds(90))
            guard isEnabled else { return }
            perform(.alignment)
            try? await Task.sleep(for: .milliseconds(90))
            guard isEnabled else { return }
            perform(.generic)
        }
    }

    private func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
