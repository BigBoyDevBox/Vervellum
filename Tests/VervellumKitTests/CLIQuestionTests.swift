import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class CLIQuestionTests: XCTestCase {

    func testJoinsAndTrimsArguments() {
        XCTAssertEqual(CLIQuestion.joined(["  What", "changed?  "][...]), "What changed?")
    }

    func testRejectsMissingAndWhitespaceOnlyArguments() {
        XCTAssertNil(CLIQuestion.joined([String]()[...]))
        XCTAssertNil(CLIQuestion.joined([" \n", "\t "][...]))
    }
}
