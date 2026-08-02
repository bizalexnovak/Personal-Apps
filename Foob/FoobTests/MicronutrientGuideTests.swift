import XCTest
@testable import Foob

final class MicronutrientGuideTests: XCTestCase {
    func testEveryTrackedFieldHasAGuideEntry() {
        // The tally's info sheet must never come up empty: every nutrient in
        // the fields table needs benefits/excess text in the guide.
        for field in Micronutrients.fields {
            let info = MicronutrientGuide.info(for: field.label)
            XCTAssertNotNil(info, "\(field.label) is missing from MicronutrientGuide")
            XCTAssertFalse(info?.goodFor.isEmpty ?? true, "\(field.label) has empty goodFor")
            XCTAssertFalse(info?.excess.isEmpty ?? true, "\(field.label) has empty excess")
        }
    }

    func testNewFieldsAreTracked() {
        let labels = Micronutrients.fields.map(\.label)
        for expected in ["Biotin (B7)", "Pantothenic acid (B5)", "Choline",
                         "Iodine", "Chromium", "Molybdenum", "Chloride"] {
            XCTAssertTrue(labels.contains(expected), "\(expected) missing from fields table")
        }
    }

    func testPreWorkoutFieldsAreTracked() {
        let labels = Micronutrients.fields.map(\.label)
        for expected in ["L-Citrulline", "Beta-alanine", "Betaine", "Taurine",
                         "L-Tyrosine", "L-Theanine", "Alpha-GPC", "L-Norvaline",
                         "Huperzine A"] {
            XCTAssertTrue(labels.contains(expected), "\(expected) missing from fields table")
        }
    }

    func testPreWorkoutFieldsSumAndScale() {
        var a = Micronutrients()
        a.citrulline = 6
        a.caffeine = 250
        var b = Micronutrients()
        b.citrulline = 2
        b.huperzineA = 50
        let sum = a.adding(b)
        XCTAssertEqual(sum.citrulline ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(sum.caffeine ?? 0, 250, accuracy: 0.001)
        XCTAssertEqual(sum.huperzineA ?? 0, 50, accuracy: 0.001)
        // Half a scoop halves the doses; unrecorded fields stay unrecorded.
        let scaled = sum.scaled(by: 0.5)
        XCTAssertEqual(scaled.citrulline ?? 0, 4, accuracy: 0.001)
        XCTAssertNil(scaled.betaAlanine)
    }

    func testNewFieldsSumAndScale() {
        var a = Micronutrients()
        a.biotin = 30
        a.pantothenicAcid = 2
        var b = Micronutrients()
        b.biotin = 15
        b.choline = 100
        let sum = a.adding(b)
        XCTAssertEqual(sum.biotin ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(sum.pantothenicAcid ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(sum.choline ?? 0, 100, accuracy: 0.001)
        let scaled = sum.scaled(by: 2)
        XCTAssertEqual(scaled.biotin ?? 0, 90, accuracy: 0.001)
        XCTAssertNil(scaled.iodine) // unrecorded stays unrecorded
    }
}
