import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

/// One formatter feeds the macOS Copy button and the Linux command line, so these
/// assertions cover both.
final class TranscriptFormatterTests: XCTestCase {

    private func turn() -> ResearchTurn {
        var turn = ResearchTurn(question: "Why?")
        turn.answer = "Because of this [1], though not that [2]."
        turn.sources = [
            Source(number: 1, url: "https://one.example.com", title: "One", snippet: ""),
            Source(number: 2, url: "https://two.example.com", title: "Two", snippet: ""),
            Source(number: 3, url: "https://three.example.com", title: "Three", snippet: ""),
        ]
        turn.findings = [
            Finding(claim: "The first thing", verdict: .supported, reasoning: "Directly stated.",
                    sourceNumbers: [1]),
            Finding(claim: "The second thing", verdict: .insufficient, reasoning: "", sourceNumbers: []),
        ]
        turn.limitations = "Only summaries."
        turn.stage = .complete
        return turn
    }

    /// Copying prose whose `[3]` markers point at nothing would be worse than useless.
    func testCarriesTheCitedSources() {
        let text = TranscriptFormatter.plainText(turn())
        XCTAssertTrue(text.contains("[1] One — https://one.example.com"))
        XCTAssertTrue(text.contains("[2] Two — https://two.example.com"))
    }

    /// A dump of everything the search returned misrepresents what the answer rests on.
    func testOmitsUncitedSources() {
        XCTAssertFalse(TranscriptFormatter.plainText(turn()).contains("three.example.com"))
    }

    /// An answer without its verdicts is exactly the confident-sounding paragraph this
    /// app exists to replace.
    func testCarriesTheVerdicts() {
        let text = TranscriptFormatter.plainText(turn())
        XCTAssertTrue(text.contains("SUPPORTED [1]: The first thing"))
        XCTAssertTrue(text.contains("NOT ESTABLISHED: The second thing"))
        XCTAssertTrue(text.contains("Directly stated."))
    }

    func testCarriesLimitationsAndNotices() {
        var subject = turn()
        subject.notices = [.noEvidence]
        let text = TranscriptFormatter.plainText(subject)
        XCTAssertTrue(text.contains("Limitations: Only summaries."))
        XCTAssertTrue(text.contains("Note: " + TurnNotice.noEvidence.message))
    }

    /// A failed turn has no answer worth printing, and saying why is the only useful
    /// thing left.
    func testAFailedTurnReportsOnlyTheFailure() {
        var subject = turn()
        subject.failure = "The provider rejected the API key."
        subject.stage = .failed
        let text = TranscriptFormatter.plainText(subject)
        XCTAssertTrue(text.contains("Failed: The provider rejected the API key."))
        XCTAssertFalse(text.contains("Sources"))
    }

    func testTheModelHelperMatchesTheFormatter() {
        XCTAssertEqual(turn().transcript, TranscriptFormatter.plainText(turn()))
    }
}
