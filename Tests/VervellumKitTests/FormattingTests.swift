import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class FormattingTests: XCTestCase {

    func testADifferentDraftIsOfferedForComparison() {
        XCTAssertTrue(DraftComparison.isOffered(draft: "First [1].", answer: "Second [1]."))
        XCTAssertFalse(DraftComparison.isOffered(draft: nil, answer: "Second [1]."))
        XCTAssertFalse(DraftComparison.isOffered(draft: "  ", answer: "Second [1]."))
        XCTAssertFalse(DraftComparison.isOffered(draft: "Same [1].\n", answer: "Same [1]."))
    }
}
