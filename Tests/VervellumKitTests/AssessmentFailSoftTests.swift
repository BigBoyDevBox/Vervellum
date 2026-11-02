import XCTest
#if canImport(FoundationNetworking)
// Linux splits URLSession out of Foundation into its own module.
import FoundationNetworking
#endif
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

/// The assessment stage must fail soft against *every* error, not only the ones this
/// codebase names.
///
/// The regression this pins used to be a real hole: the catch was narrowed to
/// `ResearchError`, while `ModelChain.perform` deliberately rethrows anything that is not
/// one. Such an error climbed out of `assess`, out of `execute`, and landed in `run`'s
/// catch — which marked the whole turn failed, discarding the answer the reader had
/// already watched arrive. `revise` had already been hardened against exactly this; the
/// assessment stage now follows it.
final class AssessmentFailSoftTests: XCTestCase {

    /// Forwards everything to a scripted stub except the assessment call, which fails
    /// with a plain `URLError`: a type no production path is supposed to leak, and
    /// therefore the exact shape of the hole.
    private struct RawFailureTransport: HTTPTransporting, @unchecked Sendable {
        let stub: StubTransport

        func sendJSON(_ request: URLRequest,
                      expectedID: Int?,
                      isNotification: Bool,
                      deadline: TimeInterval) async throws -> (headers: [String: String],
                                                               body: [String: Any]) {
            if Self.isAssessment(request) { throw URLError(.badServerResponse) }
            return try await stub.sendJSON(request, expectedID: expectedID,
                                           isNotification: isNotification, deadline: deadline)
        }

        func fetch(_ request: URLRequest, limit: Int) async throws -> (HTTPURLResponse, Data) {
            try await stub.fetch(request, limit: limit)
        }

        func streamJSONEvents(_ request: URLRequest) -> AsyncThrowingStream<[String: Any], Error> {
            stub.streamJSONEvents(request)
        }

        /// The stage is identified by its system prompt, the same way the pipeline's
        /// tests identify it: all chat calls share one endpoint.
        private static func isAssessment(_ request: URLRequest) -> Bool {
            guard let data = request.httpBody,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = object["messages"] as? [[String: Any]],
                  let prompt = messages.first?["content"] as? String
            else { return false }
            return prompt.contains("TASK: assess the material claims")
        }
    }

    func testAnUnknownAssessmentErrorKeepsTheStreamedAnswer() async {
        let stub = StubTransport { call in
            switch call.kind {
            case .json where call.url.absoluteString.hasPrefix("https://model.test/v1/chat/completions"):
                // Only the plan is routable; the assessment never reaches the stub.
                if call.systemPrompt?.contains("TASK: plan the web searches") == true {
                    return .completion(json: [
                        "reading": "A documented fact.",
                        "searches": [["purpose": "Settle it", "arguments": ["q": "fact"]]],
                    ])
                }
                return .unrouted
            case .json where call.url.path == "/search":
                return .json(["results": [
                    ["url": "https://a.example/one", "title": "One", "content": "A summary of One."],
                ]])
            case .fetch:
                return .html("<p>The page text.</p>")
            case .stream:
                return .stream(["The fact is documented [1]."])
            default:
                return .unrouted
            }
        }
        let settings = ProviderSettings(modelEndpoint: "https://model.test/v1",
                                        modelName: "test-model",
                                        searchEndpoint: "https://search.test",
                                        searchKind: .searxng,
                                        pageReading: .direct)
        let runner = ResearchRunner(
            environment: .init(settings: settings, modelKey: "key", searchKey: nil),
            trace: ResearchTrace(sink: SilentLog()),
            transport: RawFailureTransport(stub: stub),
            commandRunner: StubCommandRunner { _ in .unrouted },
            attachmentBytes: { _ in nil })

        let turn = await runner.run(ResearchTurn(question: "What is documented?"),
                                    mode: .research, history: [], onUpdate: { _ in })

        XCTAssertEqual(turn.stage, .complete,
                       "the assessment is a check on the answer, not a precondition for it")
        XCTAssertNil(turn.failure)
        XCTAssertEqual(turn.answer, "The fact is documented [1].")
        XCTAssertTrue(turn.notices.contains(.assessmentUnavailable),
                      "the reader has to be told nothing below the answer was verified")
        XCTAssertTrue(turn.findings.isEmpty)
        // The answer still got the scrutiny the citation rule always applies, even though
        // the claim check could not run.
        XCTAssertFalse(turn.notices.contains(.invalidCitation))
    }
}
