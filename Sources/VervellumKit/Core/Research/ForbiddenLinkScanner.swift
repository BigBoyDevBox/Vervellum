import Foundation

/// Finds every destination syntax the model-facing prompts forbid.
///
/// This is deliberately separate from `SourceHarvester`. Harvesting asks whether an
/// absolute HTTP address can become evidence; this scanner asks whether model-written
/// prose can express a destination at all. Scheme-relative URLs, relative Markdown
/// links and bare domains fail the second rule even though none can be fetched as a
/// source without interpretation.
///
/// Foundation's link detector is not available in swift-corelibs-foundation, so the
/// implementation stays to bounded regular expressions plus small structural checks.
/// The bare-domain pass is conservative around filenames and code-like member access:
/// a false positive puts a permanent trust warning on otherwise valid prose.
enum ForbiddenLinkScanner {

    private struct Candidate {
        var range: NSRange
        var text: String
    }

    /// Forbidden destinations, in source order. Overlapping spellings are reported
    /// once: `[docs](https://example.com)` is one violation, not a URL plus a link.
    static func links(in text: String,
                      excludingMarkdownSyntaxIn codeRanges: [Range<String.Index>] = []) -> [String] {
        guard !text.isEmpty else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var candidates: [Candidate] = []

        collect(absoluteURLRegex, in: text, range: fullRange, into: &candidates) { raw in
            let candidate = trimmingLinkPunctuation(raw)
            return SourceHarvester.normalized(candidate, trimmingPunctuation: false)
        }
        collect(hierarchicalURIRegex, in: text, range: fullRange, into: &candidates) {
            trimmingLinkPunctuation($0)
        }
        collect(commonURIRegex, in: text, range: fullRange, into: &candidates) {
            trimmingLinkPunctuation($0)
        }
        collect(markdownAutolinkRegex, in: text, range: fullRange, into: &candidates,
                excluding: codeRanges) { $0 }
        collect(schemeRelativeRegex, in: text, range: fullRange, into: &candidates) { raw in
            guard let components = URLComponents(string: "https:" + raw),
                  let host = components.host,
                  host.lowercased() == "localhost" || host.contains(".") || host.contains(":")
            else { return nil }
            return trimmingLinkPunctuation(raw)
        }
        candidates.append(contentsOf: markdownInlineLinks(in: text, excluding: codeRanges))
        collect(markdownReferenceDefinitionRegex, in: text, range: fullRange, into: &candidates,
                excluding: codeRanges) { $0 }
        collect(bareDomainRegex, in: text, range: fullRange, into: &candidates) { raw in
            let candidate = trimmingLinkPunctuation(raw)
            return isPlausibleBareDomain(candidate) ? candidate : nil
        }

        let ordered = candidates.sorted {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.range.length > $1.range.length
        }
        var distinct: [Candidate] = []
        for candidate in ordered {
            if let previous = distinct.last,
               NSIntersectionRange(previous.range, candidate.range).length > 0 {
                continue
            }
            distinct.append(candidate)
        }
        return distinct.map(\.text)
    }

    private static func collect(_ regex: NSRegularExpression?,
                                in text: String,
                                range: NSRange,
                                into candidates: inout [Candidate],
                                excluding excludedRanges: [Range<String.Index>] = [],
                                transform: (String) -> String?) {
        guard let regex else { return }
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text),
                  !isContained(swiftRange, in: excludedRanges),
                  let rendered = transform(String(text[swiftRange])),
                  !rendered.isEmpty
            else { continue }
            candidates.append(Candidate(range: match.range, text: rendered))
        }
    }

    /// Finds inline/image Markdown links with a structural walk rather than a regex.
    /// Escaped brackets, even runs of backslashes, nested destination parentheses and
    /// parenthesized titles are all significant to CommonMark, and expressing those in
    /// one regular expression either misses real links or backtracks pathologically.
    private static func markdownInlineLinks(
        in text: String,
        excluding excludedRanges: [Range<String.Index>]
    ) -> [Candidate] {
        let parentheses = matchingParentheses(in: text, excluding: excludedRanges)
        var openBrackets: [String.Index] = []
        var found: [Candidate] = []
        var index = text.startIndex
        var previousWasNewline = false
        var excludedIndex = 0

        while index < text.endIndex {
            while excludedIndex < excludedRanges.count,
                  excludedRanges[excludedIndex].upperBound <= index {
                excludedIndex += 1
            }
            if excludedIndex < excludedRanges.count,
               excludedRanges[excludedIndex].contains(index) {
                let skipped = text[excludedRanges[excludedIndex]]
                if skipped.contains(where: \.isNewline) {
                    openBrackets.removeAll(keepingCapacity: true)
                }
                index = excludedRanges[excludedIndex].upperBound
                continue
            }
            let character = text[index]
            if character.isNewline {
                // CommonMark permits one line break inside a label, but not a blank
                // paragraph. Keep the bracket stack for the former and reset it for
                // the latter so distant prose cannot be paired into a synthetic link.
                if previousWasNewline { openBrackets.removeAll(keepingCapacity: true) }
                previousWasNewline = true
                let next = text.index(after: index)
                if character == "\r", next < text.endIndex, text[next] == "\n" {
                    index = text.index(after: next)
                } else {
                    index = next
                }
                continue
            }
            previousWasNewline = false
            if character == "[", !isEscaped(index, in: text) {
                openBrackets.append(index)
                index = text.index(after: index)
                continue
            }
            guard character == "]", !isEscaped(index, in: text),
                  let opener = openBrackets.popLast()
            else {
                index = text.index(after: index)
                continue
            }

            let openParenthesis = text.index(after: index)
            guard openParenthesis < text.endIndex, text[openParenthesis] == "(",
                  let closeParenthesis = parentheses[openParenthesis]
            else {
                index = text.index(after: index)
                continue
            }
            let destinationStart = text.index(after: openParenthesis)
            let destination = text[destinationStart..<closeParenthesis]
            guard isValidInlineDestination(destination) else {
                index = text.index(after: index)
                continue
            }

            let wholeRange = opener..<text.index(after: closeParenthesis)
            if !isContained(wholeRange, in: excludedRanges) {
                found.append(Candidate(range: NSRange(wholeRange, in: text),
                                       text: String(text[wholeRange])))
            }
            openBrackets.removeAll(keepingCapacity: true)
            index = text.index(after: closeParenthesis)
        }
        return found
    }

    private static func matchingParentheses(
        in text: String,
        excluding excludedRanges: [Range<String.Index>]
    ) -> [String.Index: String.Index] {
        var stack: [String.Index] = []
        var matches: [String.Index: String.Index] = [:]
        var index = text.startIndex
        var excludedIndex = 0
        while index < text.endIndex {
            while excludedIndex < excludedRanges.count,
                  excludedRanges[excludedIndex].upperBound <= index {
                excludedIndex += 1
            }
            if excludedIndex < excludedRanges.count,
               excludedRanges[excludedIndex].contains(index) {
                let skipped = text[excludedRanges[excludedIndex]]
                if skipped.contains(where: \.isNewline) {
                    stack.removeAll(keepingCapacity: true)
                }
                index = excludedRanges[excludedIndex].upperBound
                continue
            }
            if !isEscaped(index, in: text) {
                if text[index] == "(" {
                    stack.append(index)
                } else if text[index] == ")", let opener = stack.popLast() {
                    matches[opener] = index
                }
            }
            index = text.index(after: index)
        }
        return matches
    }

    private static func isContained(_ candidate: Range<String.Index>,
                                    in excludedRanges: [Range<String.Index>]) -> Bool {
        excludedRanges.contains {
            $0.lowerBound <= candidate.lowerBound && $0.upperBound >= candidate.upperBound
        }
    }

    private static func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var cursor = index
        var slashes = 0
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            guard text[cursor] == "\\" else { break }
            slashes += 1
        }
        return !slashes.isMultiple(of: 2)
    }

    /// CommonMark permits a bare or angle-bracketed destination, then an optional
    /// single-, double-, or parenthesis-delimited title. This validation keeps prose
    /// such as `[1]: This source says …` and `[x](ordinary words here)` from becoming
    /// links merely because they contain familiar punctuation.
    private static func isValidInlineDestination(_ raw: Substring) -> Bool {
        guard !containsBlankLine(raw) else { return false }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return true }

        let remainder: Substring
        if value.first == "<" {
            guard let closer = value.indices.first(where: {
                value[$0] == ">" && !isEscaped($0, in: value)
            }) else { return false }
            remainder = value[value.index(after: closer)...]
        } else if let whitespace = value.firstIndex(where: \.isWhitespace) {
            remainder = value[whitespace...]
        } else {
            return true
        }

        let title = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return true }
        guard let first = title.first, let last = title.last else { return false }
        return (first == "\"" && last == "\"")
            || (first == "'" && last == "'")
            || (first == "(" && last == ")")
    }

    private static func containsBlankLine(_ text: Substring) -> Bool {
        var sawLineBreak = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isNewline {
                if sawLineBreak { return true }
                sawLineBreak = true
                let next = text.index(after: index)
                if character == "\r", next < text.endIndex, text[next] == "\n" {
                    index = text.index(after: next)
                } else {
                    index = next
                }
                continue
            }
            if sawLineBreak, character != " ", character != "\t" {
                sawLineBreak = false
            }
            index = text.index(after: index)
        }
        return false
    }

    private static let absoluteURLRegex = try? NSRegularExpression(
        pattern: #"(?i)(?<![A-Z0-9])https?://[^\s<>"'\\)\}]*[^\s<>"'\\)\}_*]"#)

    /// HTTP is by far the common case and receives stricter URL validation above, but
    /// any hierarchical URI still gives the model a direct destination channel.
    private static let hierarchicalURIRegex = try? NSRegularExpression(
        pattern: #"(?i)(?<![A-Z0-9+.-])[A-Z][A-Z0-9+.-]{1,31}://[^\s<>"'\\)\}]+"#)

    /// Common non-hierarchical schemes become actionable in Markdown renderers even
    /// without `//`. Keeping this set explicit avoids treating ordinary `label:value`
    /// prose as a URI merely because it happens to satisfy the generic URI grammar.
    private static let commonURIRegex = try? NSRegularExpression(
        pattern: #"(?i)(?<![A-Z0-9+.-])(?:data|facetime|file|javascript|magnet|mailto|sms|tel|webcal):[^\s<>"'\\)\}]+"#)

    /// CommonMark autolinks admit any URI scheme and email addresses inside angle
    /// brackets. The renderer can make these live even when the prose around them is
    /// otherwise plain, so the numeric-only rule must catch both forms.
    private static let markdownAutolinkRegex = try? NSRegularExpression(
        pattern: #"(?i)<(?:[A-Z][A-Z0-9+.-]{1,31}:[^ <>\r\n]+|[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9.-]*[A-Z0-9])?)>"#)

    /// Requiring a dotted host (or explicit localhost) distinguishes `//example.com`
    /// from an ordinary `// comment` without pretending a relative path is a host.
    private static let schemeRelativeRegex = try? NSRegularExpression(
        pattern: #"(?i)(?<![/:A-Z0-9_])//[^\s/<>"'\\)\}]+(?:/[^\s<>"'\\)\}]*)?"#)

    private static let markdownReferenceDefinitionRegex = try? NSRegularExpression(
        pattern: #"(?im)^[ \t]{0,3}\[(?:\\[^\r\n]|[^\]\\\r\n]|\r?\n[ \t]+)+\]:[ \t]*(?:\r?\n[ \t]{1,3})?(?:<[^<>\r\n]+>|[^ \t\r\n]+)(?:(?:[ \t]+|\r?\n[ \t]{1,3})(?:"(?:\\[^\r\n]|[^"\\\r\n])*"|'(?:\\[^\r\n]|[^'\\\r\n])*'|\((?:\\[^\r\n]|[^\)\\\r\n])*\)))?[ \t]*$"#)

    private static let bareDomainRegex = try? NSRegularExpression(
        pattern: #"(?i)(?<![@A-Z0-9_.-])(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,63}(?::\d{1,5})?(?:/[^\s<>"'\\)\]}]*)?(?![A-Z0-9_-])"#)

    private static func trimmingLinkPunctuation(_ raw: String) -> String {
        var value = raw
        while let last = value.last, ".,;:!?)]}>\"'".contains(last) {
            if last == "]", closesIPv6Host(value) { break }
            value.removeLast()
        }
        return value
    }

    private static func closesIPv6Host(_ value: String) -> Bool {
        let hostStart: String.Index?
        if let delimiter = value.range(of: "://") {
            hostStart = delimiter.upperBound
        } else if value.hasPrefix("//") {
            hostStart = value.index(value.startIndex, offsetBy: 2)
        } else {
            hostStart = nil
        }
        guard let hostStart, hostStart < value.endIndex, value[hostStart] == "[",
              let closer = value[hostStart...].firstIndex(of: "]")
        else { return false }
        return closer == value.index(before: value.endIndex)
    }

    private static func isPlausibleBareDomain(_ raw: String) -> Bool {
        if technologyDomainLookalikes.contains(raw) { return false }
        guard let components = URLComponents(string: "https://" + raw),
              let host = components.host,
              !host.isEmpty,
              let suffix = host.split(separator: ".").last?.lowercased(),
              host.contains(".")
        else { return false }

        if host.lowercased().hasPrefix("www.") { return true }
        let tld = String(suffix)
        let hasStrongDomainSignal = !components.path.isEmpty || components.port != nil
        guard !fileExtensions.contains(tld) || hasStrongDomainSignal else { return false }
        return genericTLDs.contains(tld)
            || (tld.count == 2 && !ambiguousCodeSuffixes.contains(tld))
            || (hasStrongDomainSignal && tld.allSatisfy(\.isLetter))
    }

    /// Common file suffixes that are domain-like in prose. Some are also delegated
    /// country domains (`.sh`, `.md`) or real generic domains (`.app`); without more
    /// context they are overwhelmingly filenames, and the trust UI should prefer the
    /// high-precision reading.
    private static let fileExtensions: Set<String> = [
        "7z", "a", "ai", "app", "bat", "bash", "bz2", "c", "cc", "cfg", "cmd", "conf",
        "cpp", "csv", "css", "deb", "dll", "dmg", "doc", "docx", "dylib", "exe",
        "fish", "gif", "go", "gz", "h", "hpp", "html", "ini", "java", "jpeg", "jpg",
        "js", "json", "jsx", "kt", "kts", "lock", "log", "m", "markdown", "md", "mm",
        "o", "pdf", "pbxproj", "pkg", "plist", "png", "ppt", "pptx", "ps1", "py",
        "rar", "rb", "rpm", "rs", "scala", "sh", "so", "svg", "swift", "tar", "toml",
        "ts", "tsx", "txt", "webp", "xls", "xlsx", "xcconfig", "xml", "xz", "yaml",
        "yml", "zip", "zsh",
    ]

    private static let ambiguousCodeSuffixes: Set<String> = ["as", "do", "id", "if", "in", "is", "to"]

    /// These case-sensitive tokens are product/framework names, not destinations.
    /// Lowercase spellings remain domains, as do these labels when they carry a path.
    private static let technologyDomainLookalikes: Set<String> = ["ADO.NET", "ASP.NET", "VB.NET"]

    private static let genericTLDs: Set<String> = [
        "academy", "aero", "agency", "ai", "app", "biz", "blog", "cat", "center", "cloud",
        "co", "com", "company", "coop", "dev", "digital", "edu", "email", "global", "gov",
        "group", "info", "int", "io", "jobs", "life", "live", "me", "media", "mil", "mobi",
        "museum", "name", "net", "network", "news", "one", "online", "org", "pro", "services",
        "shop", "site", "social", "solutions", "space", "store", "studio", "support", "systems",
        "tech", "today", "travel", "tv", "website", "world", "xyz",
    ]
}
