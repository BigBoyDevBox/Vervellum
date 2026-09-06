import Foundation

/// Where Vervellum sends its two kinds of request, and the rules those endpoints
/// must satisfy before a single byte leaves the machine.
///
/// Both keys live in the Keychain and are injected at call time, so this value is
/// safe to log, encode, or show in Settings — it holds no secrets.
struct ProviderSettings: Equatable, Codable {

    /// An OpenAI-compatible Chat Completions endpoint, or the API base it hangs off.
    var modelEndpoint: String
    /// The model identifier that endpoint accepts.
    var modelName: String
    /// The z.ai web-search MCP endpoint. Configurable so a self-hosted or proxied
    /// gateway can be substituted, but it defaults to the documented one.
    var searchEndpoint: String

    static let defaultSearchEndpoint = "https://api.z.ai/api/mcp/web_search_prime/mcp"

    init(modelEndpoint: String = "",
         modelName: String = "",
         searchEndpoint: String = ProviderSettings.defaultSearchEndpoint) {
        self.modelEndpoint = modelEndpoint
        self.modelName = modelName
        self.searchEndpoint = searchEndpoint
    }

    // MARK: Validation

    /// Everything that stops a research run from starting, as user-facing prose.
    /// Returns an empty array when the settings are usable.
    ///
    /// `requiresSearch` is false for the `/direct` mode, which never contacts the search
    /// server. Validating the search endpoint there would block the one mode that works
    /// when search is misconfigured — which is exactly when a user reaches for it.
    func problems(hasModelKey: Bool, hasSearchKey: Bool, requiresSearch: Bool = true) -> [String] {
        var problems: [String] = []
        if modelEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("The model endpoint is empty.")
        } else if Self.chatCompletionsURL(from: modelEndpoint) == nil {
            problems.append("The model endpoint must be an HTTPS URL (HTTP is allowed only for localhost).")
        }
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("The model name is empty.")
        }
        if requiresSearch {
            if Self.validatedEndpointURL(searchEndpoint) == nil {
                problems.append("The search endpoint must be an HTTPS URL.")
            }
            if !hasSearchKey {
                problems.append("The web-search key is missing.")
            }
        }
        // A model key is optional: a local llama.cpp or Ollama server takes none.
        _ = hasModelKey
        return problems
    }

    /// The Chat Completions URL to POST to.
    ///
    /// Providers publish their endpoint at three different levels of completeness —
    /// a bare host, a versioned base (`/v1`, `/api/paas/v4`), or the full path — and
    /// users paste whichever their provider's docs show. Appending the well-known
    /// suffix only to a bare or version-suffixed path handles all three without
    /// mangling a genuinely custom route.
    static func chatCompletionsURL(from raw: String) -> URL? {
        guard var components = validatedURLComponents(raw) else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty || versionSuffix.firstMatch(
            in: path, range: NSRange(path.startIndex..<path.endIndex, in: path)) != nil {
            path += "/chat/completions"
        }
        components.path = path
        return components.url
    }

    private static let versionSuffix = try! NSRegularExpression(pattern: #"/v[0-9]+$"#)

    /// A validated absolute endpoint URL, or nil.
    static func validatedEndpointURL(_ raw: String) -> URL? {
        validatedURLComponents(raw)?.url
    }

    /// Shared endpoint hygiene.
    ///
    /// * **HTTPS required**, with an exception for loopback so a local model server
    ///   works without a certificate. Plain HTTP to a remote host would put the API
    ///   key on the wire in clear text.
    /// * **No userinfo.** A `https://key@host/` URL leaks the credential into every
    ///   log line and `Referer`; Vervellum sends keys in headers only.
    /// * **A host is required**, so a typo like `https:/v1` can't resolve to
    ///   something unexpected.
    private static func validatedURLComponents(_ raw: String) -> URLComponents? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        if scheme == "https" { return components }
        if scheme == "http", isLoopback(host) { return components }
        return nil
    }

    private static func isLoopback(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return bare == "localhost" || bare == "127.0.0.1" || bare == "::1"
    }
}
