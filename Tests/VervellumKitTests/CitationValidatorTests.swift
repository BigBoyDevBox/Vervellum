import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

final class CitationValidatorTests: XCTestCase {

    func testInlineCodeCannotCrossRenderedBlockBoundaries() {
        let answers = [
            "- `open [1]\n- [2] close`",
            "# `open [1]\n[2] close`",
            "| `open [1] | [2] close` |\n| --- | --- |",
        ]
        for answer in answers {
            let result = CitationValidator.validate(answer: answer, sourceCount: 2)
            XCTAssertEqual(result.citedSourceIndices, [0, 1], answer)
            XCTAssertFalse(ResearchContext.withoutCitationMarkers(answer).contains("[1]"))
        }
    }

    func testCRLFFencesDoNotHideFollowingProseCitations() {
        let answer = "```swift\r\nitems[0]\r\n```\r\nFact [1]."
        let result = CitationValidator.validate(answer: answer, sourceCount: 1)
        XCTAssertEqual(result.citedSourceIndices, [0])
        XCTAssertTrue(result.outOfRangeCitations.isEmpty)
    }

    func testEscapedBackticksRemainProse() {
        let answer = #"Escaped \` prose [1] \`."#
        XCTAssertEqual(CitationValidator.validate(answer: answer, sourceCount: 1).citedSourceIndices, [0])
    }

    func testMultilineInlineCodeDoesNotBecomeACitation() {
        let answer = "`items\n[0]` then fact [1]."
        let result = CitationValidator.validate(answer: answer, sourceCount: 1)
        XCTAssertEqual(result.citedSourceIndices, [0])
        XCTAssertTrue(result.outOfRangeCitations.isEmpty)
    }

    func testSplitsTextAndCitations() {
        let result = CitationValidator.validate(answer: "Swift is fast [1] and safe [2].", sourceCount: 3)
        XCTAssertEqual(result.spans, [
            .text("Swift is fast "),
            .citation(sourceIndices: [0], raw: "[1]"),
            .text(" and safe "),
            .citation(sourceIndices: [1], raw: "[2]"),
            .text("."),
        ])
        XCTAssertEqual(result.citedSourceIndices, [0, 1])
        XCTAssertTrue(result.isClean)
    }

    func testParsesMultiNumberCitations() {
        let result = CitationValidator.validate(answer: "Both agree [1, 3].", sourceCount: 3)
        XCTAssertEqual(result.citedSourceIndices, [0, 2])
        XCTAssertTrue(result.isClean)
    }

    /// An out-of-range number is a fabricated citation. It must be reported, and the
    /// marker must degrade to plain text rather than becoming a chip to nowhere.
    func testFlagsOutOfRangeCitations() {
        let result = CitationValidator.validate(answer: "As shown [7].", sourceCount: 2)
        XCTAssertEqual(result.outOfRangeCitations, [7])
        XCTAssertFalse(result.isClean)
        XCTAssertEqual(result.spans, [.text("As shown "), .text("[7]"), .text(".")])
    }

    func testKeepsValidNumbersFromAPartlyInventedMarker() {
        let result = CitationValidator.validate(answer: "Mixed [1, 9].", sourceCount: 2)
        XCTAssertEqual(result.citedSourceIndices, [0])
        XCTAssertEqual(result.outOfRangeCitations, [9])
    }

    /// The answer prompt forbids URLs outright, so one appearing is a prompt
    /// violation the UI has to warn about.
    func testFlagsLiteralURLs() {
        let result = CitationValidator.validate(
            answer: "See https://example.com/made-up for details.", sourceCount: 2)
        XCTAssertEqual(result.forbiddenLinks, ["https://example.com/made-up"])
        XCTAssertFalse(result.isClean)
    }

    /// The prompt forbids every syntax in which the model could smuggle a destination,
    /// not only the absolute HTTP spelling the source harvester happens to ingest.
    func testFlagsSchemeRelativeMarkdownAndBareDomainLinks() {
        for answer in [
            "See //example.com/a for details.",
            "See [the documentation](/private/path) for details.",
            "See example.com/a for details.",
            "Even `example.com/private` inside code is still a model-written link.",
        ] {
            let result = CitationValidator.validate(answer: answer, sourceCount: 1)
            XCTAssertFalse(result.forbiddenLinks.isEmpty, answer)
            XCTAssertFalse(result.isClean, answer)
        }
    }

    /// Domain-like punctuation occurs constantly in legitimate prose and code. The
    /// link gate must stay precise enough that filenames, versions, emails, member
    /// access and a comment opener do not put a trust warning on an answer.
    func testDomainScanDoesNotFlagCommonNonLinks() {
        let answer = """
            Version 1.2.3 uses README.md, package.json, archive.tar.gz, main.swift,
            build.sh and Vervellum.app. Email me@example.com. Call object.property,
            `items[i](x)`, or write // comment. An escaped \\[label](/not-a-link) is text.
            ```swift
            [key](value)
            ```
            """
        let result = CitationValidator.validate(answer: answer, sourceCount: 0)
        XCTAssertTrue(result.forbiddenLinks.isEmpty, "\(result.forbiddenLinks)")
        XCTAssertTrue(result.isClean)
    }

    func testLinkScanTerminatesOnLongPunctuationHeavyText() {
        let answer = String(repeating: "a.b-c_1/[]() ", count: 20_000) + "example.com"
        let result = CitationValidator.validate(answer: answer, sourceCount: 0)
        XCTAssertEqual(result.forbiddenLinks.last, "example.com")
    }

    func testAdjacentCitationsAreNotMistakenForAReferenceLink() {
        let result = CitationValidator.validate(answer: "Both claims [1][2].", sourceCount: 2)
        XCTAssertEqual(result.citedSourceIndices, [0, 1])
        XCTAssertTrue(result.forbiddenLinks.isEmpty)
    }

    /// A markdown link is not a citation marker, and neither is a bracketed aside.
    func testMarkdownLinksAndProseBracketsAreNotCitationMarkers() {
        let markdown = CitationValidator.validate(answer: "[docs](https://example.com)", sourceCount: 3)
        XCTAssertEqual(markdown.citedSourceIndices, [])
        let aside = CitationValidator.validate(answer: "an aside [see below] here", sourceCount: 3)
        XCTAssertEqual(aside.citedSourceIndices, [])
    }

    func testHandlesEmptyAnswer() {
        let result = CitationValidator.validate(answer: "", sourceCount: 0)
        XCTAssertEqual(result.spans, [.text("")])
        XCTAssertTrue(result.isClean)
    }

    func testZeroSourcesMakesEveryCitationInvalid() {
        let result = CitationValidator.validate(answer: "Claim [1].", sourceCount: 0)
        XCTAssertEqual(result.outOfRangeCitations, [1])
        XCTAssertEqual(result.citedSourceIndices, [])
    }

    // MARK: Code is not prose

    /// `argv[0]` in a code sample is an index, not an invented source 0.
    func testBracketsInsideAFencedBlockAreNotCitations() {
        let answer = "Use the first argument [1].\n\n```python\nfirst = sys.argv[0]\nnext = items[1]\n```\n\nDone [2]."
        let result = CitationValidator.validate(answer: answer, sourceCount: 2)
        XCTAssertEqual(result.outOfRangeCitations, [])
        XCTAssertEqual(result.citedSourceIndices, [0, 1])
        XCTAssertTrue(result.isClean)
    }

    func testBracketsInsideInlineCodeAreNotCitations() {
        let result = CitationValidator.validate(answer: "Read `argv[1]` first [2].", sourceCount: 2)
        XCTAssertEqual(result.citedSourceIndices, [1])
        XCTAssertEqual(result.spans, [.text("Read `argv[1]` first "),
                                      .citation(sourceIndices: [1], raw: "[2]"),
                                      .text(".")])
    }

    /// A double-backtick span may contain a single backtick.
    func testDoubleBacktickSpansAreCode() {
        let result = CitationValidator.validate(answer: "``a ` b[1]`` and [1].", sourceCount: 1)
        XCTAssertEqual(result.spans.filter { if case .citation = $0 { return true } else { return false } }.count, 1)
    }

    /// Mid-stream the closing fence has not arrived; everything after the opener is
    /// code, exactly as the renderer draws it.
    func testAnUnterminatedFenceIsCodeToTheEnd() {
        let result = CitationValidator.validate(answer: "Intro [1].\n```\nx = a[2]\ny = b[3", sourceCount: 1)
        XCTAssertEqual(result.citedSourceIndices, [0])
        XCTAssertEqual(result.outOfRangeCitations, [])
    }

    /// A lone backtick is a literal backtick, not a span that swallows the line.
    func testAnUnclosedBacktickDoesNotHideProse() {
        let result = CitationValidator.validate(answer: "A stray ` here, then a real citation [1].", sourceCount: 1)
        XCTAssertEqual(result.citedSourceIndices, [0])
    }

    func testCodeRangesCoverFencesAndSpans() {
        let text = "a `b` c\n~~~\nd\n~~~\ne"
        let ranges = CitationValidator.codeRanges(in: text)
        XCTAssertEqual(ranges.map { String(text[$0]) }, ["`b`", "~~~\nd\n~~~"])
    }
}
