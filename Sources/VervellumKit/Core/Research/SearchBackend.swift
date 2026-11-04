import Foundation

/// What the research pipeline needs from a web-search provider, whatever protocol it
/// speaks.
///
/// The pipeline never knew much about search: it asks for a tool descriptor, hands that
/// to the planner so the model writes arguments against a real schema, and walks
/// whatever comes back with `EvidenceExtractor`, which matches on *shape* rather than
/// on one provider's field names. This protocol is that contract written down, so a
/// backend that is not an MCP server can be added without the runner learning about it.
///
/// The implementations differ in one interesting way. An MCP server *advertises* its own
/// tool and schema, and `SearchMCPClient` fetches it rather than assuming; a SearXNG
/// instance and the Kagi CLI have no such advertisement, so those clients supply the
/// schema themselves. Either way the planner is given a real schema, and the arguments it
/// writes are checked against that schema before a request goes out.
///
/// One of them is not a server at all. `KagiCLIClient` runs a program on the user's own
/// machine, which is why this protocol says nothing about transports: what a backend
/// needs to reach its index is the backend's business, and the pipeline's business is a
/// schema, a call and a result.
protocol SearchBackend: AnyObject {

    /// A name for the log and for user-facing prose. Never a provider's own text.
    var backendName: String { get }

    /// The tool as the planner is shown it: `name`, an optional `description`, and an
    /// `inputSchema`. Meaningless before `connect()` has returned.
    var toolDescriptor: [String: Any] { get }

    /// Establishes whatever the backend needs before a search — a protocol handshake,
    /// a tool listing, a key check. Called once, before planning, so a rejected key
    /// fails before the billable planning call rather than after it.
    func connect() async throws

    /// Runs one search with arguments the model wrote. The result is handed to
    /// `EvidenceExtractor` untouched.
    func search(arguments: [String: Any]) async throws -> Any

    /// Whether several searches may be in flight on this backend at once.
    ///
    /// A SearXNG instance or a CLI invocation is one stateless request per call. An
    /// MCP server is a session with a single JSON-RPC id sequence over one
    /// connection, and interleaved calls would scramble it — the runner fans out only
    /// over backends that say true here and keeps the rest serial.
    var supportsConcurrentCalls: Bool { get }
}

extension SearchBackend {

    /// The conservative default: serialised. A conformer that says nothing is safe
    /// without knowing the protocol underneath.
    var supportsConcurrentCalls: Bool { false }
}

extension SearchBackend {

    /// Checks model-written arguments against an advertised schema.
    ///
    /// A missing required key or an invented one means the model misread the schema,
    /// and sending it anyway spends a request to get a provider-side error back. Shared
    /// because the check belongs to the *contract*, not to any one protocol.
    ///
    /// Names only. What a value is *allowed to be* — an enum, a format, a range — is
    /// described by the schema and not enforced here, so a backend that turns a value
    /// into something more dangerous than a query parameter has to check it itself. See
    /// `KagiCLIClient.command(for:)`, where a value becomes a command-line argument.
    func validate(_ arguments: [String: Any],
                  required: [String],
                  properties: Set<String>) throws {
        let keys = Set(arguments.keys)
        guard required.allSatisfy({ keys.contains($0) }) else {
            throw ResearchError("The model omitted a required search argument. Try another model.")
        }
        if !properties.isEmpty, !keys.isSubset(of: properties) {
            throw ResearchError("The model produced unknown search arguments. Try another model.")
        }
    }

    /// Rewrites a plan from its planner's schema to this backend's schema for deep
    /// research fan-out.
    ///
    /// Only the query crosses that boundary. Optional filters are provider-specific:
    /// a `language` accepted by one backend can mean something else on another, and an
    /// enum in JSON Schema describes a value without validating it here. Guessing would
    /// turn a harmless planning option into a different request. A backend with another
    /// required field is therefore incompatible with this plan and is skipped.
    ///
    /// The backend the plan was written for receives the original dictionary. Its own
    /// `search(arguments:)` remains the authority on that schema, including useful
    /// provider-specific filters.
    func projectedArguments(from arguments: [String: Any],
                            plannedAgainst planningBackend: SearchBackend)
        -> [String: Any]? {
        guard case .arguments(let projected) = projection(
            from: arguments, plannedAgainst: planningBackend) else { return nil }
        return projected
    }

    /// The runner also needs to distinguish a backend it can never translate this
    /// planner's schema to from one skipped because a single step carried a bad value.
    /// The first should leave later rounds; the second may accept their next query.
    func projection(from arguments: [String: Any],
                    plannedAgainst planningBackend: SearchBackend)
        -> SearchArgumentProjection.Outcome {
        if ObjectIdentifier(self) == ObjectIdentifier(planningBackend) {
            return .arguments(arguments)
        }
        guard let targetSchema = projectionSchema,
              let targetName = targetSchema.canonicalQueryKey(),
              targetSchema.required.isSubset(of: [targetName])
        else { return .incompatibleSchema }

        switch planningBackend.queryForFanOut(from: arguments) {
        case .query(let query):
            return .arguments([targetName: query])
        case .invalidArguments:
            return .invalidArguments
        case .incompatibleSchema:
            return .incompatibleSchema
        }
    }

    /// Extracts the one portable value in a search plan, after proving the model wrote
    /// arguments that belong to the planner's advertised schema. This is deliberately
    /// stricter than `validate`: a missing property list cannot safely be projected to
    /// a different backend, even though an individual backend may have a reason to
    /// accept such a schema itself.
    private func queryForFanOut(from arguments: [String: Any])
        -> SearchArgumentProjection.Query {
        guard let schema = projectionSchema else { return .incompatibleSchema }
        let recognized = schema.recognizedQueryKeys
        let requiredRecognized = recognized.filter(schema.required.contains)
        guard !recognized.isEmpty, requiredRecognized.count <= 1
        else { return .incompatibleSchema }

        let name: String
        if let required = requiredRecognized.first {
            name = required
        } else {
            // No required recognised query key. A required string we do not
            // recognise is, in practice, the query under a provider-specific
            // name; an optional recognised key must not stand in for it. This
            // mirrors the target side's `required.isSubset(of: [targetName])`:
            // both sides must reject the same schema, or a planner like
            // `{q: optional, filters: required}` would be unwritable as a target
            // yet silently donate its optional `q` as though it were the query.
            guard schema.required.isDisjoint(with: schema.stringProperties)
            else { return .incompatibleSchema }
            let present = recognized.filter { arguments[$0] != nil }
            guard present.count == 1, let only = present.first
            else { return .invalidArguments }
            name = only
        }
        let keys = Set(arguments.keys)
        guard schema.required.isSubset(of: keys),
              keys.isSubset(of: schema.properties) else { return .invalidArguments }

        guard let query = arguments[name] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .invalidArguments }
        return .query(query)
    }

    /// The schema facts projection needs, or nil when the descriptor is too vague to
    /// translate without guessing. An absent `required` is valid JSON Schema and means
    /// no required properties; a malformed one is not treated as the same thing.
    private var projectionSchema: SearchArgumentProjection.Schema? {
        guard let input = toolDescriptor["inputSchema"] as? [String: Any],
              let rawProperties = input["properties"] as? [String: Any],
              !rawProperties.isEmpty else { return nil }

        let required: Set<String>
        if let rawRequired = input["required"] {
            guard let names = rawRequired as? [String] else { return nil }
            required = Set(names)
        } else {
            required = []
        }

        var strings: Set<String> = []
        for (name, rawSchema) in rawProperties {
            guard let property = rawSchema as? [String: Any] else { continue }
            if property["type"] as? String == "string"
                || (property["type"] as? [String])?.contains("string") == true {
                strings.insert(name)
            }
        }
        return SearchArgumentProjection.Schema(
            properties: Set(rawProperties.keys), required: required,
            stringProperties: strings)
    }
}

/// Search schemas use several conventional names for the same one portable concept.
/// Kept finite on purpose: descriptions and arbitrary required fields are model- and
/// provider-written text, not a safe basis for deciding what becomes a request.
enum SearchArgumentProjection {
    enum Outcome {
        case arguments([String: Any])
        case invalidArguments
        case incompatibleSchema
    }

    enum Query {
        case query(String)
        case invalidArguments
        case incompatibleSchema
    }

    struct Schema {
        let properties: Set<String>
        let required: Set<String>
        let stringProperties: Set<String>

        var recognizedQueryKeys: [String] {
            PlannedSearch.queryArgumentNames.filter(stringProperties.contains)
        }

        /// A required conventional query field is authoritative. When none is required,
        /// exactly one recognized string property is still unambiguous; two optional
        /// spellings are not.
        func canonicalQueryKey() -> String? {
            let recognized = recognizedQueryKeys
            let requiredRecognized = recognized.filter(required.contains)
            if requiredRecognized.count == 1 { return requiredRecognized[0] }
            if requiredRecognized.count > 1 { return nil }
            return recognized.count == 1 ? recognized[0] : nil
        }
    }
}

/// Builds the backend a `SearchProfile` describes.
///
/// A free function rather than a `SearchProviderKind` method: constructing one needs a
/// transport and a trace, and giving a `Codable` settings enum those dependencies would
/// drag the network layer into the settings file.
enum SearchBackendFactory {

    /// - Throws: when the profile's endpoint is not usable, or a key the kind requires
    ///   is missing. Both are configuration problems, reported before any request.
    static func make(profile: SearchProfile,
                     apiKey: String?,
                     trace: ResearchTrace,
                     transport: any HTTPTransporting = HTTPTransport.shared,
                     commandRunner: any CommandRunning = CommandRunner.shared) throws -> SearchBackend {
        switch profile.kind {
        case .mcp:
            guard let url = ProviderSettings.validatedEndpointURL(profile.endpoint) else {
                throw ResearchError("The search endpoint is not a usable URL. Check the provider settings.")
            }
            guard let apiKey, !apiKey.isEmpty else {
                throw ResearchError("The web-search key is missing. Check the provider settings.")
            }
            return SearchMCPClient(endpoint: url, apiKey: apiKey, trace: trace, transport: transport)
        case .searxng:
            guard let url = ProviderSettings.searxngSearchURL(from: profile.endpoint) else {
                throw ResearchError("The SearXNG address is not a usable URL. Check the provider settings.")
            }
            // The key stays optional: a SearXNG instance is usually open, or fronted by
            // a proxy that wants a bearer token. Demanding one would block the most
            // common self-hosted setup.
            return SearXNGClient(searchURL: url, apiKey: apiKey, trace: trace, transport: transport)
        case .kagiCLI:
            // `profile.endpoint` is not a URL for this kind: it holds a command, either a
            // bare name to look for or a full path to one. The field's meaning follows
            // the kind, which is why the settings pane puts the picker above it.
            //
            // Resolved here, so "you have not installed it" is reported with the rest of
            // the configuration problems and before the turn's first billable call —
            // rather than surfacing as a failed search a minute into a run.
            guard let executable = commandRunner.resolve(command: profile.endpoint) else {
                // Naming what was looked for is most of the message: `kagi-cli` typed
                // where `kagi` was meant is indistinguishable from a missing install
                // otherwise, and both are one edit away from working.
                throw ResearchError(
                    "Vervellum could not find the Kagi command-line tool "
                    + "\"\(profile.endpoint)\". Install it from "
                    + "https://github.com/Microck/kagi-cli, or put its full path in the "
                    + "provider settings.")
            }
            // The key stays optional, and is usually absent: `kagi auth` holds the
            // credential. One stored here is passed to the tool as `KAGI_API_KEY`.
            return KagiCLIClient(executable: executable, apiKey: apiKey, trace: trace,
                                 runner: commandRunner)
        case .unsupported:
            // Preserve the row for a newer build, but never guess which protocol it
            // speaks. In particular, no key or request may leave this process here.
            throw ResearchError("The selected search provider type is not supported by "
                                + "this version. Choose a supported provider in Settings.")
        }
    }
}
