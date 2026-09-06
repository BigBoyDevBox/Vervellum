import XCTest
@testable import Vervellum

/// macOS-only: the Accessibility path has no Linux counterpart.
final class SelectedTextReaderTests: XCTestCase {

    func testSelectionIsTrimmedAndCapped() {
        XCTAssertEqual(SelectedTextReader.trim("  hello  "), "hello")
        let long = String(repeating: "word ", count: 4000)
        let trimmed = SelectedTextReader.trim(long, limit: 100)
        XCTAssertLessThanOrEqual(trimmed.count, 101)
        XCTAssertTrue(trimmed.hasSuffix("…"))
    }

    func testShortSelectionIsUntouched() {
        XCTAssertEqual(SelectedTextReader.trim("a question", limit: 100), "a question")
    }
}
