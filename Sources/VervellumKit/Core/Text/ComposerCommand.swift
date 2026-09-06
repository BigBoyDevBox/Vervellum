import Foundation

/// A slash command typed into the composer.
///
/// Slash commands exist because the panel is summoned by a shortcut and dismissed by
/// one: reaching for a toolbar button breaks the flow that made the shortcut worth
/// having. Everything reachable from the header is therefore also reachable by
/// typing, and the composer's own placeholder advertises it.
///
/// Parsing is deliberately strict. A leading slash only counts as a command when the
/// word that follows is one Vervellum knows — otherwise "/etc/hosts is world
/// readable, right?" would silently become an unknown-command error instead of a
/// question.
///
/// Pure and dependency-free, so it is fully unit-testable.
enum ComposerCommand: Equatable {
    /// Research normally.
    case ask(String)
    /// Answer without searching.
    case direct(String)
    case newThread
    case openHistory
    case openSettings
    case copyLastAnswer
    case showHelp

    /// One command as the completion list shows it.
    ///
    /// A named struct rather than a tuple: a key path cannot reference a tuple element
    /// (`\.name` on `(name: String, …)` is rejected outright), which rules out both
    /// `ForEach(_:id:)` and `map(\.name)` — and both are wanted.
    struct Entry: Identifiable, Equatable {
        var name: String
        var summary: String
        var id: String { name }
    }

    /// Commands offered in the composer's completion list.
    static let catalogue: [Entry] = [
        Entry(name: "direct", summary: "Answer from the model alone, with no web evidence"),
        Entry(name: "new", summary: "Start a fresh thread"),
        Entry(name: "history", summary: "Search earlier threads"),
        Entry(name: "settings", summary: "Open Vervellum Settings"),
        Entry(name: "copy", summary: "Copy the last answer with its sources"),
        Entry(name: "help", summary: "List the commands"),
    ]

    /// Parses composer text. Returns nil for input that is only whitespace.
    static func parse(_ input: String) -> ComposerCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("/") else { return .ask(trimmed) }

        let body = trimmed.dropFirst()
        let split = body.firstIndex(where: { $0.isWhitespace })
        let word = String(split.map { body[..<$0] } ?? body).lowercased()
        let rest = split.map { String(body[$0...]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

        switch word {
        case "direct":
            // "/direct" with nothing after it is a mode request with no question yet,
            // not an empty question — leave it to the caller to keep the composer open.
            return rest.isEmpty ? nil : .direct(rest)
        case "new", "clear":
            return .newThread
        case "history", "threads":
            return .openHistory
        case "settings", "prefs", "preferences":
            return .openSettings
        case "copy":
            return .copyLastAnswer
        case "help", "?":
            return .showHelp
        default:
            // Not a command Vervellum knows: it is part of the question.
            return .ask(trimmed)
        }
    }

    /// Command names matching a partially typed `/prefix`, for the completion list.
    /// Returns nil when the input is not a bare command word being typed.
    static func completions(for input: String) -> [Entry]? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/"), !trimmed.dropFirst().contains(where: { $0.isWhitespace })
        else { return nil }
        let prefix = String(trimmed.dropFirst()).lowercased()
        let matches = catalogue.filter { $0.name.hasPrefix(prefix) }
        return matches.isEmpty ? nil : matches
    }

    /// The help text `/help` prints into the thread.
    static var helpText: String {
        let rows = catalogue.map { "- `/\($0.name)` — \($0.summary)" }.joined(separator: "\n")
        return """
            ## Commands

            \(rows)

            ## Keys

            - `Return` — ask (`Shift-Return` for a new line; swap them in Settings)
            - `⌘Return` — ask, whichever way Return is configured
            - `Esc` — clear the draft, then close the panel
            - `↑` / `↓` — earlier questions in this thread
            - `⌘N` — new thread
            - `⌘Y` — earlier threads
            - `⌘.` — stop the running research
            - `⌘,` — Settings
            - `⌘W` — close the panel
            """
    }
}
