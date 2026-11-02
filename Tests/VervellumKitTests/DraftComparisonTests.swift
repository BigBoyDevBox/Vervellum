import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

final class DraftComparisonTests: XCTestCase {

    func testADifferentDraftIsOfferedForComparison() {
        XCTAssertTrue(DraftComparison.isOffered(draft: "First [1].", answer: "Second [1]."))
        XCTAssertFalse(DraftComparison.isOffered(draft: nil, answer: "Second [1]."))
        XCTAssertFalse(DraftComparison.isOffered(draft: "  ", answer: "Second [1]."))
        XCTAssertFalse(DraftComparison.isOffered(draft: "Same [1].\n", answer: "Same [1]."))
    }
}
