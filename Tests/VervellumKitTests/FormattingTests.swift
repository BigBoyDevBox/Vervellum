import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

final class FormattingTests: XCTestCase {

    /// The Linux history list cannot use `RelativeDateTimeFormatter` (absent from
    /// corelibs), so `relativeDate` is the whole age column. Its steps are pinned so
    /// a rewrite cannot quietly change what a row claims.
    func testRelativeDateUsesNarrowSteps() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Formatting.relativeDate(now, from: now), "just now")
        XCTAssertEqual(Formatting.relativeDate(now.addingTimeInterval(-30), from: now), "just now")
        XCTAssertEqual(Formatting.relativeDate(now.addingTimeInterval(-4 * 60), from: now), "4m ago")
        XCTAssertEqual(Formatting.relativeDate(now.addingTimeInterval(-3 * 3600), from: now), "3h ago")
        XCTAssertEqual(Formatting.relativeDate(now.addingTimeInterval(-2 * 86_400), from: now), "2d ago")
        XCTAssertEqual(Formatting.relativeDate(now.addingTimeInterval(-21 * 86_400), from: now), "3w ago")
        // Past two months the token becomes a calendar date rather than a count —
        // matched loosely because the formatter speaks the machine's zone.
        let far = Formatting.relativeDate(now.addingTimeInterval(-90 * 86_400), from: now)
        XCTAssertNotNil(far.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression), far)
        // A clock jump backwards is not from the future.
        XCTAssertEqual(Formatting.relativeDate(now.addingTimeInterval(60), from: now), "just now")
    }
}
