import Foundation

/// Math for the portion-adjust slider. The slider position runs -1…1 with 1×
/// at the centre (0); dragging left shrinks the portion, right grows it. The
/// mapping is multiplicative (position → factor = maxFactor^position) so the
/// control is symmetric: +0.5 doubles-ish, -0.5 halves-ish, and 1× sits dead
/// centre instead of being skewed by a linear 0.25…4 range.
enum PortionScale {
    /// Slider spans 1/maxFactor× … maxFactor× (e.g. 0.25× … 4×).
    static let maxFactor: Double = 4
    static var minFactor: Double { 1 / maxFactor }

    /// Snap points the slider is magnetic toward (and the tick marks shown).
    static let detents: [Double] = [0.25, 0.5, 1, 2, 3, 4]

    static func factor(for position: Double) -> Double {
        pow(maxFactor, position)
    }

    static func position(for factor: Double) -> Double {
        guard factor > 0 else { return 0 }
        return (log(factor) / log(maxFactor)).clamped(to: -1...1)
    }

    static func clampFactor(_ factor: Double) -> Double {
        factor.clamped(to: minFactor...maxFactor)
    }

    /// Snap a slider position to the nearest detent when it's close.
    static func snap(_ position: Double, threshold: Double = 0.05) -> Double {
        var best = position
        var bestDistance = threshold
        for detent in detents {
            let dp = self.position(for: detent)
            let distance = abs(dp - position)
            if distance < bestDistance {
                bestDistance = distance
                best = dp
            }
        }
        return best
    }

    /// Plain multiplier number for the text field ("2", "0.5", "1.5").
    static func numberText(_ factor: Double) -> String {
        let rounded = (factor * 100).rounded() / 100
        if rounded == rounded.rounded() { return "\(Int(rounded))" }
        if (rounded * 10).rounded() / 10 == rounded { return String(format: "%.1f", rounded) }
        return String(format: "%.2f", rounded)
    }

    /// Short tick label for a detent ("½", "1", "2").
    static func tickLabel(_ factor: Double) -> String {
        switch factor {
        case 0.25: return "¼"
        case 0.5: return "½"
        default: return numberText(factor)
        }
    }

    /// Compact multiplier label: "1×", "1.5×", "0.67×".
    static func label(_ factor: Double) -> String {
        let rounded = (factor * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        if (rounded * 10).rounded() / 10 == rounded {
            return String(format: "%.1f×", rounded)
        }
        return String(format: "%.2f×", rounded)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
