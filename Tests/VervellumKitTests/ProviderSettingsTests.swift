import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

final class ProviderSettingsTests: XCTestCase {

    // MARK: URL shaping

    /// Providers document their endpoint at three different levels of completeness,
    /// and users paste whichever their provider's docs show.
    func testAppendsChatCompletionsToAVersionedBase() {
        XCTAssertEqual(ProviderSettings.chatCompletionsURL(from: "https://api.example.com/v1")?.absoluteString,
                       "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(ProviderSettings.chatCompletionsURL(from: "https://api.example.com/v1/")?.absoluteString,
                       "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(ProviderSettings.chatCompletionsURL(from: "https://api.example.com/api/paas/v4")?.absoluteString,
                       "https://api.example.com/api/paas/v4/chat/completions")
    }

    func testAppendsChatCompletionsToABareHost() {
        XCTAssertEqual(ProviderSettings.chatCompletionsURL(from: "https://api.example.com")?.absoluteString,
                       "https://api.example.com/chat/completions")
    }

    func testPreservesAFullOrCustomPath() {
        XCTAssertEqual(
            ProviderSettings.chatCompletionsURL(from: "https://api.example.com/v1/chat/completions")?.absoluteString,
            "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(
            ProviderSettings.chatCompletionsURL(from: "https://gateway.example.com/llm/route")?.absoluteString,
            "https://gateway.example.com/llm/route")
    }

    // MARK: Endpoint hygiene

    func testRejectsPlainHTTPToARemoteHost() {
        XCTAssertNil(ProviderSettings.chatCompletionsURL(from: "http://api.example.com/v1"))
    }

    /// A local model server has no certificate; refusing HTTP outright would make
    /// Ollama and llama.cpp unusable for no security gain.
    func testAllowsHTTPOnLoopback() {
        XCTAssertNotNil(ProviderSettings.chatCompletionsURL(from: "http://localhost:11434/v1"))
        XCTAssertNotNil(ProviderSettings.chatCompletionsURL(from: "http://127.0.0.1:8080/v1"))
    }

    /// A credential in the URL would leak into logs and Referer headers. Keys belong
    /// in a header.
    func testRejectsURLsCarryingUserInfo() {
        XCTAssertNil(ProviderSettings.chatCompletionsURL(from: "https://secret@api.example.com/v1"))
        XCTAssertNil(ProviderSettings.chatCompletionsURL(from: "https://user:pass@api.example.com/v1"))
    }

    func testRejectsEmptyAndHostlessInput() {
        XCTAssertNil(ProviderSettings.chatCompletionsURL(from: ""))
        XCTAssertNil(ProviderSettings.chatCompletionsURL(from: "   "))
        XCTAssertNil(ProviderSettings.chatCompletionsURL(from: "https:/v1"))
    }

    // MARK: Readiness

    func testReportsEveryMissingPiece() {
        let problems = ProviderSettings(modelEndpoint: "", modelName: "")
            .problems(hasModelKey: false, hasSearchKey: false)
        XCTAssertEqual(problems.count, 3)
    }

    /// A local model server needs no key, so a missing model key must not block a run.
    func testAModelKeyIsOptional() {
        let settings = ProviderSettings(modelEndpoint: "https://api.example.com/v1", modelName: "m")
        XCTAssertTrue(settings.problems(hasModelKey: false, hasSearchKey: true).isEmpty)
    }

    func testASearchKeyIsRequired() {
        let settings = ProviderSettings(modelEndpoint: "https://api.example.com/v1", modelName: "m")
        XCTAssertEqual(settings.problems(hasModelKey: true, hasSearchKey: false).count, 1)
    }

    /// `/direct` never contacts the search server, so a broken search endpoint — or no
    /// search key at all — must not block the one mode that still works when search is
    /// misconfigured. That is exactly when someone reaches for it.
    func testDirectModeIgnoresTheSearchConfiguration() {
        let settings = ProviderSettings(modelEndpoint: "https://api.example.com/v1",
                                        modelName: "m",
                                        searchEndpoint: "not-a-url")
        XCTAssertTrue(settings.problems(hasModelKey: true, hasSearchKey: false,
                                        requiresSearch: false).isEmpty)
        XCTAssertFalse(settings.problems(hasModelKey: true, hasSearchKey: false).isEmpty)
    }

    /// A missing *model* endpoint still blocks direct mode: that one it does contact.
    func testDirectModeStillNeedsTheModelEndpoint() {
        let settings = ProviderSettings(modelEndpoint: "", modelName: "")
        XCTAssertEqual(settings.problems(hasModelKey: true, hasSearchKey: true,
                                         requiresSearch: false).count, 2)
    }

    func testRejectsANonHTTPSSearchEndpoint() {
        let settings = ProviderSettings(modelEndpoint: "https://api.example.com/v1",
                                        modelName: "m",
                                        searchEndpoint: "http://search.example.com/mcp")
        XCTAssertFalse(settings.problems(hasModelKey: true, hasSearchKey: true).isEmpty)
    }
}
