import SwiftUI

struct HapticSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>

    @State private var reachedLowerBoundary = false
    @State private var reachedUpperBoundary = false

    var body: some View {
        Slider(value: hapticBinding, in: range)
    }

    private var hapticBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                value = newValue
                handleBoundaryHaptics(newValue)
            }
        )
    }

    private func handleBoundaryHaptics(_ newValue: Double) {
        let epsilon = max((range.upperBound - range.lowerBound) * 0.002, 0.001)
        let isAtLowerBoundary = newValue <= range.lowerBound + epsilon
        let isAtUpperBoundary = newValue >= range.upperBound - epsilon

        if isAtLowerBoundary, !reachedLowerBoundary {
            reachedLowerBoundary = true
            HapticManager.shared.sliderBoundaryReached()
        } else if !isAtLowerBoundary {
            reachedLowerBoundary = false
        }

        if isAtUpperBoundary, !reachedUpperBoundary {
            reachedUpperBoundary = true
            HapticManager.shared.sliderBoundaryReached()
        } else if !isAtUpperBoundary {
            reachedUpperBoundary = false
        }
    }
}
