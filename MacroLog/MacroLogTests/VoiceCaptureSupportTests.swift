import XCTest
@testable import MacroLog

/// The mic/speech session itself can't run headless, but the hand-off flag
/// and the recognition-biasing vocabulary are plain logic worth pinning down.
@MainActor
final class VoiceCaptureSupportTests: XCTestCase {
    func testCaptureRequestsCarryTheRightMode() {
        let store = PendingMealStore()
        XCTAssertNil(store.request)

        store.requestVoice()
        XCTAssertEqual(store.request?.mode, .voice)

        store.requestScan()
        XCTAssertEqual(store.request?.mode, .scan)

        store.requestText("two eggs")
        XCTAssertEqual(store.request?.mode, .text("two eggs"))
    }

    func testFoodVocabularyCoversBrandsProteinsAndUnits() {
        let vocabulary = SpeechCaptureController.foodVocabulary
        XCTAssertGreaterThan(vocabulary.count, 40)
        XCTAssertTrue(vocabulary.contains("Chobani"))
        XCTAssertTrue(vocabulary.contains("turkey bacon"))
        XCTAssertTrue(vocabulary.contains("ounces"))
        XCTAssertEqual(Set(vocabulary).count, vocabulary.count, "no duplicate contextual strings")
    }
}
