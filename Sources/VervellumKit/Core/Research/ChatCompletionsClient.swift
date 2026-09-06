import Foundation

/// Talks to an OpenAI-compatible Chat Completions endpoint.
///
/// Vervellum needs two different shapes from the same endpoint, and they are kept
/// separate on purpose:
///
/// * `completeJSON` — a **non-streaming** call whose whole reply must parse as one
///   JSON object. Used for the search plan and the claim assessment, where a
///   half-formed reply is worthless and strict validation is the point.
/// * `streamText` — a **streaming** call whose deltas are handed to the UI as they
///   arrive. Used for the prose answer, where the first token mattering within a
///   second is worth more than structure.
///
/// The endpoint is untrusted: it is whatever URL the user pasted. So the JSON path
/// re-parses defensively and every failure becomes a `ResearchError` naming the
/// likely fix, rather than a decoding trace the user cannot act on.
struct ChatCompletionsClient {

    let url: URL
    let model: String
    let apiKey: String?
    let trace: ResearchTrace
    var transport: HTTPTransport = .shared

    private var headers: [String: String] {
        guard let apiKey, !apiKey.isEmpty else { return [:] }
        return ["Authorization": "Bearer " + apiKey]
    }

    // MARK: Structured call

    /// Sends `system` plus a JSON-encoded `payload` and decodes the reply as a JSON
    /// object.
    func completeJSON(system: String, payload: Any, label: String) async throws -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(payload),
              let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let userContent = String(data: encoded, encoding: .utf8)
        else { throw ResearchError("Vervellum could not encode the request context.") }

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            // Deterministic-ish: these two calls are extraction and adjudication, not
            // composition, and sampling variance there shows up as flaky validation.
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        // `"stream": false` above, so do not advertise SSE — see HTTPTransport.request.
        let request = try HTTPTransport.request(url: url, payload: body, headers: headers,
                                                acceptsEventStream: false)
        let (_, response) = try await trace.stage(label) {
            try await transport.sendJSON(request)
        }
        let text = try Self.messageContent(from: response)
        guard let object = Self.decodeJSONObject(from: text) else {
            throw ResearchError("The model did not return the requested JSON. "
                                + "Try again, or choose a model that follows JSON instructions.")
        }
        return object
    }

    // MARK: Streaming call

    /// Streams a prose reply, invoking `onDelta` for each chunk, and returns the full
    /// accumulated text.
    ///
    /// `onDelta` is called on whichever thread the stream is being consumed on, and is
    /// deliberately *not* `@MainActor`. Marshalling belongs to the caller because the
    /// platforms answer it differently: on macOS the main actor is the main dispatch
    /// queue, but a GTK application runs a GLib main loop instead, so a `MainActor` hop
    /// there would never execute and the answer would never appear.
    func streamText(system: String,
                    payload: Any,
                    label: String,
                    onDelta: @escaping (String) -> Void) async throws -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let userContent = String(data: encoded, encoding: .utf8)
        else { throw ResearchError("Vervellum could not encode the request context.") }

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        let request = try HTTPTransport.request(url: url, payload: body, headers: headers,
                                                acceptsEventStream: true)

        trace.log("\(label) started")
        let began = Date()
        var accumulated = ""
        var finishReason: String?

        do {
            for try await event in transport.streamJSONEvents(request) {
                try Task.checkCancellation()
                // A gateway that ignored `stream: true` sends one complete response
                // object; take its message content wholesale.
                if let whole = try? Self.messageContent(from: event), !whole.isEmpty, accumulated.isEmpty {
                    accumulated = whole
                    onDelta(whole)
                    continue
                }
                guard let choices = event["choices"] as? [[String: Any]],
                      let first = choices.first else { continue }
                if let reason = first["finish_reason"] as? String { finishReason = reason }
                guard let delta = first["delta"] as? [String: Any],
                      let chunk = delta["content"] as? String, !chunk.isEmpty else { continue }
                accumulated += chunk
                onDelta(chunk)
            }
        } catch let error as ResearchError {
            trace.warn(String(format: "%@ failed after %.2fs: %@", label,
                              Date().timeIntervalSince(began), error.message))
            throw error
        } catch is CancellationError {
            throw ResearchError.cancelled
        } catch {
            throw ResearchError.connectionFailed
        }

        try Self.checkFinishReason(finishReason)
        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResearchError("The model returned an empty answer. Try again or choose another model.")
        }
        trace.log(String(format: "%@ completed in %.2fs, %d characters", label,
                         Date().timeIntervalSince(began), accumulated.count))
        return accumulated
    }

    // MARK: Response shaping

    /// The assistant message text from a non-streaming Chat Completions response.
    static func messageContent(from response: [String: Any]) throws -> String {
        guard let choices = response["choices"] as? [[String: Any]], let first = choices.first else {
            // A provider that returns its own error object instead of `choices` is the
            // single most common misconfiguration (wrong path, wrong model name).
            throw ResearchError("The model endpoint did not return a completion. "
                                + "Check the endpoint path and model name in Settings ▸ Providers.")
        }
        try checkFinishReason(first["finish_reason"] as? String)
        guard let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ResearchError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func checkFinishReason(_ reason: String?) throws {
        switch reason {
        case "length":
            throw ResearchError("The model's reply was cut off by its output limit. "
                                + "Try a shorter question or a model with a larger output limit.")
        case "content_filter":
            throw ResearchError("The model's provider filtered the reply. Try rephrasing the question.")
        default:
            return
        }
    }

    /// Decodes a JSON object from a model reply, tolerating the two things models do
    /// even when told not to: wrapping the object in a ```json fence, and prefixing
    /// it with a sentence of commentary.
    static func decodeJSONObject(from text: String) -> [String: Any]? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```") {
            candidate = stripFence(candidate)
        }
        if let object = parseObject(candidate) { return object }
        // Fall back to the outermost brace-balanced run, which recovers a reply that
        // has prose wrapped around the object.
        guard let braced = outermostObject(in: candidate) else { return nil }
        return parseObject(braced)
    }

    private static func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Removes a surrounding ``` fence.
    ///
    /// Handles the one-line form — ```` ```json {"a": 1} ``` ```` — separately, because
    /// dropping "the first line" there discards the entire object and leaves nothing to
    /// parse. Models produce that shape often enough for a short reply.
    private static func stripFence(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        if lines.count == 1 {
            var single = Substring(text)
            single = single.drop(while: { $0 == "`" })
            while let last = single.last, last == "`" { single = single.dropLast() }
            // Drop an info string such as `json` that is now leading the content.
            let trimmed = single.trimmingCharacters(in: .whitespaces)
            if let brace = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) {
                return String(trimmed[brace...])
            }
            return trimmed
        }
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The substring from the first `{` to its matching `}`, ignoring braces inside
    /// string literals so a brace in prose content cannot end the scan early.
    static func outermostObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" && inString {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
