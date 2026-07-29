import XCTest
@testable import MindLog

final class BreathingExerciseTests: XCTestCase {
    func testCycleDurations() {
        XCTAssertEqual(BreathingPattern.box.cycleDuration, 16, accuracy: 0.001)
        XCTAssertEqual(BreathingPattern.fourSevenEight.cycleDuration, 19, accuracy: 0.001)
        XCTAssertEqual(BreathingPattern.coherent.cycleDuration, 11, accuracy: 0.001)
    }

    func testBoxPhaseSequence() {
        let box = BreathingPattern.box
        XCTAssertEqual(box.position(at: 0).step.kind, .inhale)
        XCTAssertEqual(box.position(at: 3.9).step.kind, .inhale)
        XCTAssertEqual(box.position(at: 4.0).step.kind, .hold)
        XCTAssertEqual(box.position(at: 8.5).step.kind, .exhale)
        XCTAssertEqual(box.position(at: 12.5).step.kind, .rest)
    }

    func testPositionWrapsAcrossCycles() {
        let box = BreathingPattern.box
        let pos = box.position(at: 16 * 2 + 5) // third cycle, 5 s in
        XCTAssertEqual(pos.cycleIndex, 2)
        XCTAssertEqual(pos.step.kind, .hold)
        XCTAssertEqual(pos.elapsedInStep, 1, accuracy: 0.001)
    }

    func testStepProgressRunsZeroToOne() {
        let box = BreathingPattern.box
        XCTAssertEqual(box.position(at: 0).stepProgress, 0, accuracy: 0.001)
        XCTAssertEqual(box.position(at: 2).stepProgress, 0.5, accuracy: 0.001)
        XCTAssertLessThan(box.position(at: 3.999).stepProgress, 1.0)
    }

    func testNegativeElapsedClampsToStart() {
        let pos = BreathingPattern.box.position(at: -5)
        XCTAssertEqual(pos.cycleIndex, 0)
        XCTAssertEqual(pos.stepIndex, 0)
        XCTAssertEqual(pos.elapsedInStep, 0, accuracy: 0.001)
    }

    func testScaleGrowsOnInhaleAndShrinksOnExhale() {
        let coherent = BreathingPattern.coherent // 5.5 in, 5.5 out
        let early = coherent.scale(at: 0.5)
        let peak = coherent.scale(at: 5.49)
        let falling = coherent.scale(at: 8.0)
        let bottom = coherent.scale(at: 10.99)
        XCTAssertLessThan(early, peak)
        XCTAssertEqual(peak, 1.0, accuracy: 0.01)
        XCTAssertLessThan(falling, peak)
        XCTAssertEqual(bottom, BreathStep.baseScale, accuracy: 0.01)
    }

    func testScaleHoldsSteadyDuringHolds() {
        let box = BreathingPattern.box
        // Hold after inhale stays at full expansion.
        XCTAssertEqual(box.scale(at: 5), 1.0, accuracy: 0.001)
        XCTAssertEqual(box.scale(at: 7.9), 1.0, accuracy: 0.001)
        // Rest after exhale stays at the base.
        XCTAssertEqual(box.scale(at: 13), BreathStep.baseScale, accuracy: 0.001)
    }

    func testScaleStaysWithinBounds() {
        for pattern in BreathingPattern.all {
            for t in stride(from: 0.0, through: pattern.cycleDuration * 3, by: 0.1) {
                let s = pattern.scale(at: t)
                XCTAssertGreaterThanOrEqual(s, BreathStep.baseScale - 0.001, "\(pattern.id) @ \(t)")
                XCTAssertLessThanOrEqual(s, 1.001, "\(pattern.id) @ \(t)")
            }
        }
    }

    func testAllPatternsStartWithAnInhale() {
        for pattern in BreathingPattern.all {
            XCTAssertEqual(pattern.steps.first?.kind, .inhale, pattern.id)
        }
    }
}
