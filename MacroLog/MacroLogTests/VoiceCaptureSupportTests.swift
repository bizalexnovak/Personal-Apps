import XCTest
@testable import MacroLog

/// The mic/speech session itself can't run headless, but the hand-off flag
/// and the recognition-biasing vocabulary are plain logic worth pinning down.
@MainActor
final class VoiceCaptureSupportTests: XCTestCase {
    func testVoiceCaptureRequestConsumesOnce() {
        let store = PendingMealStore()
        XCTAssertFalse(store.consumeVoiceCaptureRequest())

        store.requestVoiceCapture()
        XCTAssertTrue(store.consumeVoiceCaptureRequest())
        XCTAssertFalse(store.consumeVoiceCaptureRequest(), "flag must clear after consumption")
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
