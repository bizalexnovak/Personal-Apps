import Foundation

/// One step of a breathing cycle. `scale` is where the guide circle should be
/// by the END of the step (1 = fully expanded lungs, base = fully exhaled) —
/// the view animates between the previous step's scale and this one.
struct BreathStep: Equatable {
    enum Kind: String { case inhale, hold, exhale, rest }

    let kind: Kind
    let seconds: Double

    var label: String {
        switch kind {
        case .inhale: return "Breathe in"
        case .hold: return "Hold"
        case .exhale: return "Breathe out"
        case .rest: return "Rest"
        }
    }

    /// Guide-circle scale at the end of this step.
    var endScale: Double {
        switch kind {
        case .inhale: return 1.0
        case .hold: return 1.0
        case .exhale: return BreathStep.baseScale
        case .rest: return BreathStep.baseScale
        }
    }

    static let baseScale = 0.55
}

/// A named breathing pattern: the repeating cycle plus display copy.
/// `position(at:)` is pure time→state math so the animation is fully testable.
struct BreathingPattern: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let steps: [BreathStep]

    var cycleDuration: Double { steps.reduce(0) { $0 + $1.seconds } }

    /// Where in the exercise a given elapsed time falls.
    struct Position: Equatable {
        var cycleIndex: Int
        var stepIndex: Int
        var step: BreathStep
        var elapsedInStep: Double
        /// 0…1 progress through the current step.
        var stepProgress: Double
    }

    func position(at elapsed: Double) -> Position {
        let cycle = cycleDuration
        let safeElapsed = max(0, elapsed)
        let cycleIndex = cycle > 0 ? Int(safeElapsed / cycle) : 0
        var remainder = cycle > 0 ? safeElapsed.truncatingRemainder(dividingBy: cycle) : 0
        for (index, step) in steps.enumerated() {
            if remainder < step.seconds || index == steps.count - 1 {
                let inStep = min(remainder, step.seconds)
                return Position(
                    cycleIndex: cycleIndex,
                    stepIndex: index,
                    step: step,
                    elapsedInStep: inStep,
                    stepProgress: step.seconds > 0 ? inStep / step.seconds : 1
                )
            }
            remainder -= step.seconds
        }
        // Unreachable (the loop always returns on the last step), but keeps
        // the compiler satisfied for an empty-steps pattern.
        return Position(
            cycleIndex: 0, stepIndex: 0,
            step: BreathStep(kind: .rest, seconds: 1),
            elapsedInStep: 0, stepProgress: 0
        )
    }

    /// Guide-circle scale at `elapsed`, interpolating through the current
    /// step from the previous step's end scale.
    func scale(at elapsed: Double) -> Double {
        guard !steps.isEmpty else { return BreathStep.baseScale }
        let pos = position(at: elapsed)
        let previousIndex = (pos.stepIndex + steps.count - 1) % steps.count
        let from = steps[previousIndex].endScale
        let to = pos.step.endScale
        // Ease in/out so the circle breathes rather than lurches.
        let t = pos.stepProgress
        let eased = t * t * (3 - 2 * t)
        return from + (to - from) * eased
    }

    // MARK: - The built-in patterns

    static let box = BreathingPattern(
        id: "box", name: "Box breathing", subtitle: "4 in · 4 hold · 4 out · 4 hold",
        steps: [
            BreathStep(kind: .inhale, seconds: 4),
            BreathStep(kind: .hold, seconds: 4),
            BreathStep(kind: .exhale, seconds: 4),
            BreathStep(kind: .rest, seconds: 4),
        ]
    )

    static let fourSevenEight = BreathingPattern(
        id: "478", name: "4-7-8", subtitle: "4 in · 7 hold · 8 out — for winding down",
        steps: [
            BreathStep(kind: .inhale, seconds: 4),
            BreathStep(kind: .hold, seconds: 7),
            BreathStep(kind: .exhale, seconds: 8),
        ]
    )

    static let coherent = BreathingPattern(
        id: "coherent", name: "Coherent", subtitle: "5½ in · 5½ out — steady and even",
        steps: [
            BreathStep(kind: .inhale, seconds: 5.5),
            BreathStep(kind: .exhale, seconds: 5.5),
        ]
    )

    static let all: [BreathingPattern] = [box, fourSevenEight, coherent]
}
