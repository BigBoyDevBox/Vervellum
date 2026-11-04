import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class ForbiddenLinkScannerTests: XCTestCase {

    func testFindsEveryDestinationSpelling() {
        let examples = [
            "HTTPS://EXAMPLE.COM/path",
            "http://[::1]:8080/path",
            "http://[::1]",
            "https://[2001:db8::1].",
            "_https://example.com_",
            "//example.com/path",
            "//[2001:db8::1]/path",
            "//[::1]",
            "//user@example.com/path",
            "[label](/relative/path)",
            "See[docs](/relative/path)",
            "[](/relative/path)",
            #"[la\]bel](/relative/path)"#,
            #"\\[label](/relative/path)"#,
            "[outer [inner] text](/relative/path)",
            "[label\ntext](/relative/path)",
            "[label\r\ntext](/relative/path)",
            "[label](/relative/path (title))",
            "[label](\n/relative/path)",
            "[label](/relative/path\n)",
            #"[label](<foo\>bar>)"#,
            "![alt](image)",
            "[destination]: /relative/path",
            "[proof][la\\]bel]\n\n[la\\]bel]: /private",
            "[proof][x]\n\n[x]:\n  /private",
            "[proof][x]\n\n[x]: /private \"a \\\" title\"",
            "[proof][foo bar]\n\n[foo\n bar]: /private",
            "mailto:user@example.com",
            "<custom+app:open/item>",
            "<user@example.com>",
            "file:/private/report.txt",
            "data:text/plain,private",
            "tel:+41441234567",
            "example.com/path",
            "example.ai/path",
            "example.app/path",
            "example.sh/path",
            "example.design/path",
            "docs.example.co.uk/path",
            "www.example.invalid/path",
        ]
        for example in examples {
            XCTAssertFalse(ForbiddenLinkScanner.links(in: example).isEmpty, example)
        }
    }

    func testIgnoresHighFrequencyDomainAndMarkdownLookalikes() {
        let examples = [
            "3.14", "v1.2.3", "README.md", "package.json", "archive.tar.gz", "drawing.ai",
            "main.swift", "build.sh", "Vervellum.app", "alice@example.com",
            "ASP.NET", "VB.NET", "ADO.NET",
            "object.property", "// comment", "/usr/local/bin", "[1][2]", "[term][case]",
            "[1]: This source says the claim is supported",
            "[1]", "[1, 2]", #"\[label](/escaped)"#, "example.com_value",
        ]
        for example in examples {
            XCTAssertTrue(ForbiddenLinkScanner.links(in: example).isEmpty, example)
        }
    }

    func testMarkdownShapedCodeIsSyntaxButDestinationsInCodeStillFail() {
        let text = "Use `[key](value)` and `<user@example.com>` here.\n"
            + "```swift\n[label](value)\n```"
        XCTAssertTrue(ForbiddenLinkScanner.links(
            in: text, excludingMarkdownSyntaxIn: CitationValidator.codeRanges(in: text)).isEmpty)

        let linkedCode = "`example.com/private` and ```\nhttps://example.org/private\n```"
        XCTAssertEqual(ForbiddenLinkScanner.links(
            in: linkedCode,
            excludingMarkdownSyntaxIn: CitationValidator.codeRanges(in: linkedCode)).count, 2)
    }

    func testInlineCodeInsideALinkLabelDoesNotHideTheOuterDestination() {
        for text in ["[foo `[x]` bar](/relative)", "[foo `[` bar](/relative)"] {
            XCTAssertFalse(ForbiddenLinkScanner.links(
                in: text,
                excludingMarkdownSyntaxIn: CitationValidator.codeRanges(in: text)).isEmpty,
                text)
        }
    }

    func testOverlappingSyntaxIsOneViolation() {
        XCTAssertEqual(ForbiddenLinkScanner.links(in: "[docs](https://example.com)").count, 1)
    }

    func testManyRealMatchesAreDeduplicatedWithoutQuadraticWork() {
        let text = (0..<2_000).map { "host\($0).example.com" }.joined(separator: " ")
        XCTAssertEqual(ForbiddenLinkScanner.links(in: text).count, 2_000)
    }
}
