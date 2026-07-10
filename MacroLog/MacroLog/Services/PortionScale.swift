import Foundation

/// Math for the portion-adjust slider. The slider position runs -1…1 with 1×
/// at the centre (0); dragging left shrinks the portion, right grows it. The
/// mapping is multiplicative (position → factor = maxFactor^position) so the
/// control is symmetric: +0.5 doubles-ish, -0.5 halves-ish, and 1× sits dead
/// centre instead of being skewed by a linear 0.25…4 range.
enum PortionScale {
    /// Slider spans 1/maxFactor× … maxFactor× (e.g. 0.25× … 4×).
    static let maxFactor: Double = 4

    static func factor(for position: Double) -> Double {
        pow(maxFactor, position)
    }

    static func position(for factor: Double) -> Double {
        guard factor > 0 else { return 0 }
        return (log(factor) / log(maxFactor)).clamped(to: -1...1)
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
