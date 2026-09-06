import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

final class SourceHarvesterTests: XCTestCase {

    func testFindsLinkKeysAtAnyDepth() {
        let payload: [String: Any] = [
            "results": [
                ["title": "One", "url": "https://example.com/a"],
                ["title": "Two", "link": "https://example.org/b"],
                ["nested": ["deep": ["href": "https://example.net/c"]]],
            ],
        ]
        XCTAssertEqual(SourceHarvester.urls(in: payload),
                       ["https://example.com/a", "https://example.org/b", "https://example.net/c"])
    }

    /// The z.ai MCP server returns its real payload as a JSON string inside a text
    /// content block. Missing that would leave the allow-list empty and reject every
    /// citation the model made.
    func testParsesJSONEmbeddedInAnMCPTextBlock() {
        let inner = #"{"results":[{"url":"https://example.com/inner"}]}"#
        let payload: [String: Any] = ["content": [["type": "text", "text": inner]]]
        XCTAssertEqual(SourceHarvester.urls(in: payload), ["https://example.com/inner"])
    }

    func testFindsBareURLsInProse() {
        let payload = ["summary": "See https://example.com/page, and https://example.org/other."]
        XCTAssertEqual(SourceHarvester.urls(in: payload),
                       ["https://example.com/page", "https://example.org/other"])
    }

    /// A favicon is not a source. Allowing icon fields through would let a model
    /// "cite" a CDN image.
    func testSkipsIconFields() {
        let payload: [String: Any] = [
            "icon": "https://cdn.example.com/favicon.ico",
            "favicon": "https://cdn.example.com/fav.png",
            "site_icon": "https://cdn.example.com/site.png",
            "url": "https://example.com/real",
        ]
        XCTAssertEqual(SourceHarvester.urls(in: payload), ["https://example.com/real"])
    }

    func testRejectsNonHTTPAndHostlessURLs() {
        XCTAssertNil(SourceHarvester.normalized("ftp://example.com/x"))
        XCTAssertNil(SourceHarvester.normalized("javascript:alert(1)"))
        XCTAssertNil(SourceHarvester.normalized("https://"))
        XCTAssertNil(SourceHarvester.normalized("not a url"))
        XCTAssertNotNil(SourceHarvester.normalized("http://localhost:8080/x"))
    }

    /// A URL that ends a sentence picks up the punctuation. The allow-list and the
    /// audit scan must strip it identically or a legitimate citation fails.
    func testTrimsTrailingPunctuation() {
        XCTAssertEqual(SourceHarvester.normalized("https://example.com/a."), "https://example.com/a")
        XCTAssertEqual(SourceHarvester.normalized("https://example.com/a),"), "https://example.com/a")
        XCTAssertEqual(SourceHarvester.normalized("https://example.com/a\""), "https://example.com/a")
    }

    func testDeeplyNestedPayloadTerminates() {
        var nested: Any = ["url": "https://example.com/deep"]
        for _ in 0..<200 { nested = ["next": nested] }
        // The depth guard means the innermost URL is not found; what matters is that
        // this returns at all rather than recursing until the stack gives out.
        XCTAssertTrue(SourceHarvester.urls(in: nested).isEmpty)
    }

    func testHandlesEmptyAndScalarInput() {
        XCTAssertTrue(SourceHarvester.urls(in: nil).isEmpty)
        XCTAssertTrue(SourceHarvester.urls(in: 42).isEmpty)
        XCTAssertTrue(SourceHarvester.urls(in: [String: Any]()).isEmpty)
    }
}
