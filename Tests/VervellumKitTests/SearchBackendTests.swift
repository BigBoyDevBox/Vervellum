import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class SearchBackendTests: XCTestCase {

    private final class Backend: SearchBackend {
        let backendName: String
        let toolDescriptor: [String: Any]

        init(name: String = "test", properties: [String: Any], required: [String]) {
            backendName = name
            toolDescriptor = [
                "name": name,
                "inputSchema": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ]
        }

        func connect() async throws {}
        func search(arguments: [String: Any]) async throws -> Any { [:] as [String: Any] }
    }

    private static let string: [String: Any] = ["type": "string"]

    func testProjectionKeepsOnlyThePortableQuery() throws {
        let planner = Backend(
            properties: [
                "q": Self.string,
                "language": Self.string,
                "categories": Self.string,
            ],
            required: ["q"])
        let spare = Backend(
            properties: ["query": Self.string, "locale": Self.string],
            required: ["query"])

        let projected = spare.projectedArguments(
            from: ["q": "swift actors", "language": "en", "categories": "it"],
            plannedAgainst: planner)

        XCTAssertEqual(projected as? [String: String], ["query": "swift actors"])
    }

    func testProjectionRecognisesSearchQueryAndUnionStringSchemas() throws {
        let planner = Backend(
            properties: ["q": Self.string], required: ["q"])
        let spare = Backend(
            properties: ["search_query": ["type": ["null", "string"]]],
            required: ["search_query"])

        let projected = spare.projectedArguments(
            from: ["q": "portable query"], plannedAgainst: planner)

        XCTAssertEqual(projected as? [String: String],
                       ["search_query": "portable query"])
    }

    func testProjectionRejectsAnAdditionalRequiredArgument() {
        let planner = Backend(
            properties: ["q": Self.string], required: ["q"])
        let spare = Backend(
            properties: ["query": Self.string, "locale": Self.string],
            required: ["query", "locale"])

        XCTAssertNil(spare.projectedArguments(
            from: ["q": "portable query"], plannedAgainst: planner))
    }

    func testProjectionRejectsUnknownAndNonStringQuerySchemas() {
        let planner = Backend(
            properties: ["q": Self.string], required: ["q"])
        let unknown = Backend(
            properties: ["term": Self.string], required: ["term"])
        let numeric = Backend(
            properties: ["query": ["type": "integer"]], required: ["query"])

        XCTAssertNil(unknown.projectedArguments(
            from: ["q": "portable query"], plannedAgainst: planner))
        XCTAssertNil(numeric.projectedArguments(
            from: ["q": "portable query"], plannedAgainst: planner))
    }

    func testProjectionRejectsAnAmbiguousTargetQueryField() {
        let planner = Backend(
            properties: ["q": Self.string], required: ["q"])
        let spare = Backend(
            properties: ["query": Self.string, "q": Self.string], required: [])

        XCTAssertNil(spare.projectedArguments(
            from: ["q": "portable query"], plannedAgainst: planner))
    }

    func testRequiredPlannerQueryWinsOverAnOptionalSpelling() throws {
        let planner = Backend(
            properties: ["q": Self.string, "text": Self.string], required: ["text"])
        let spare = Backend(
            properties: ["query": Self.string], required: ["query"])

        let projected = try XCTUnwrap(spare.projectedArguments(
            from: ["q": "optional value", "text": "required value"],
            plannedAgainst: planner))

        XCTAssertEqual(projected as? [String: String], ["query": "required value"])
    }

    /// The planner-side mirror of `testProjectionRejectsAnAdditionalRequiredArgument`:
    /// a schema that requires a string this code does not recognise is rejected as a
    /// target, so it must be rejected as a planner too. Before the guard it was
    /// accepted, and the sole optional recognised key stood in for a query that may
    /// well live in the required field — sent to every spare as though it were real.
    /// `.incompatibleSchema`, not `.invalidArguments`: the schema, not one step's
    /// values, is the problem, so the engine is retired for the rest of the turn.
    func testProjectionRejectsAPlannerRequiringAnUnrecognisedString() {
        let planner = Backend(
            properties: ["q": Self.string, "filters": Self.string],
            required: ["filters"])
        let spare = Backend(
            properties: ["query": Self.string], required: ["query"])

        switch spare.projection(
            from: ["q": "not the query", "filters": "the real query"],
            plannedAgainst: planner) {
        case .incompatibleSchema:
            break
        case .arguments, .invalidArguments:
            XCTFail("a required unrecognised string must retire the planner for "
                    + "projection, not donate its optional recognised key")
        }
    }

    func testOptionalPlannerQueryIsResolvedPerStep() throws {
        let planner = Backend(
            properties: ["q": Self.string, "query": Self.string], required: [])
        let spare = Backend(
            properties: ["text": Self.string], required: [])

        XCTAssertNil(spare.projectedArguments(
            from: [:], plannedAgainst: planner))
        XCTAssertNil(spare.projectedArguments(
            from: ["q": "one", "query": "two"], plannedAgainst: planner))
        XCTAssertEqual(try XCTUnwrap(spare.projectedArguments(
            from: ["q": "one"], plannedAgainst: planner)) as? [String: String],
            ["text": "one"])
    }

    func testProjectionRejectsMalformedPlannerArguments() {
        let planner = Backend(
            properties: ["q": Self.string], required: ["q"])
        let spare = Backend(
            properties: ["query": Self.string], required: ["query"])

        XCTAssertNil(spare.projectedArguments(
            from: ["q": "portable query", "invented": "filter"],
            plannedAgainst: planner))
        XCTAssertNil(spare.projectedArguments(
            from: ["q": 42], plannedAgainst: planner))
        XCTAssertNil(spare.projectedArguments(
            from: ["q": "   "], plannedAgainst: planner))
    }

    func testPlanningBackendKeepsItsOriginalArguments() throws {
        let planner = Backend(
            properties: ["q": Self.string, "language": Self.string],
            required: ["q"])
        let original: [String: Any] = ["q": "swift", "language": "de"]

        let projected = try XCTUnwrap(planner.projectedArguments(
            from: original, plannedAgainst: planner))

        XCTAssertEqual(projected["q"] as? String, "swift")
        XCTAssertEqual(projected["language"] as? String, "de")
        XCTAssertEqual(Set(projected.keys), ["q", "language"])
    }
}
