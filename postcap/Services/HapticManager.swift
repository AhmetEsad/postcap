import AppKit
import Foundation

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let defaultsKey = "hapticFeedbackEnabled"
    private var lastTimelineTick = ContinuousClock.now

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    func timelineScrubbed(
        from oldValue: Double,
        to newValue: Double,
        range: ClosedRange<Double>,
        markers: [Double]
    ) {
        guard isEnabled else { return }

        let endpointEpsilon = max((range.upperBound - range.lowerBound) * 0.002, 0.001)
        guard newValue > range.lowerBound + endpointEpsilon,
              newValue < range.upperBound - endpointEpsilon else {
            return
        }

        for marker in markers {
            let crossedMarker = (oldValue < marker && newValue >= marker)
                || (oldValue > marker && newValue <= marker)
            if crossedMarker {
                perform(.levelChange)
                return
            }
        }

        let now = ContinuousClock.now
        guard now - lastTimelineTick >= .milliseconds(35) else { return }
        lastTimelineTick = now
        perform(.alignment)
    }

    func sliderBoundaryReached() {
        guard isEnabled else { return }
        perform(.generic)
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
