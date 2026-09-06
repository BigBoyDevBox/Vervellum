import Foundation

/// Validates and parses the numeric citations in a model's answer.
///
/// Vervellum's answer prompt forbids the model from writing URLs at all: it may
/// only refer to evidence by the index of a source Vervellum itself fetched, as
/// `[3]` or `[1, 4]`. That single rule is what makes a fabricated link
/// *structurally impossible* rather than merely discouraged — there is no syntax in
/// which the model could express one, and any URL that appears anyway is a prompt
/// violation the validator can flag on sight.
///
/// Checking indices is also cheaper and far more reliable than string-matching URLs:
/// a model that reformats a link (adds a tracking parameter, drops a trailing slash,
/// percent-encodes a character) would fail an exact-match allow-list even though it
/// cited a real source. An integer either is or isn't in range.
///
/// Pure and dependency-free, so it is fully unit-testable.
enum CitationValidator {

    /// One piece of a parsed answer: either literal text, or a citation referring to
    /// `sourceIndices` (already converted to zero-based positions in the source list).
    enum Span: Equatable {
        case text(String)
        case citation(sourceIndices: [Int], raw: String)
    }

    /// What validation found. `isClean` is the only thing the UI gates trust on.
    struct Result: Equatable {
        /// The answer split into renderable spans, in order.
        var spans: [Span]
        /// Zero-based source indices actually cited, ascending.
        var citedSourceIndices: [Int]
        /// Citation numbers outside `1...sourceCount` that the model invented.
        var outOfRangeCitations: [Int]
        /// Literal URLs the model wrote despite being told not to.
        var literalURLs: [String]

        var isClean: Bool { outOfRangeCitations.isEmpty && literalURLs.isEmpty }
    }

    /// Matches `[3]`, `[3, 4]`, `[3,4 , 12]` — digits and separators only, so an
    /// ordinary markdown link `[text](url)` or a bracketed aside never matches.
    private static let citationRegex = try? NSRegularExpression(
        pattern: #"\[\s*\d{1,3}(?:\s*[,;]\s*\d{1,3})*\s*\]"#)

    /// Parses `answer` against a source list of `sourceCount` entries.
    static func validate(answer: String, sourceCount: Int) -> Result {
        var spans: [Span] = []
        var cited: Set<Int> = []
        var outOfRange: [Int] = []

        guard let regex = citationRegex else {
            return Result(spans: [.text(answer)], citedSourceIndices: [],
                          outOfRangeCitations: [], literalURLs: SourceHarvester.bareURLs(in: answer))
        }

        let full = NSRange(answer.startIndex..<answer.endIndex, in: answer)
        var cursor = answer.startIndex

        for match in regex.matches(in: answer, range: full) {
            guard let range = Range(match.range, in: answer) else { continue }
            if cursor < range.lowerBound {
                spans.append(.text(String(answer[cursor..<range.lowerBound])))
            }
            let raw = String(answer[range])
            let numbers = raw
                .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " })
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

            var indices: [Int] = []
            for number in numbers {
                if number >= 1 && number <= sourceCount {
                    indices.append(number - 1)
                    cited.insert(number - 1)
                } else {
                    outOfRange.append(number)
                }
            }
            // A marker whose every number was invented is kept as plain text rather
            // than rendered as a chip that leads nowhere.
            if indices.isEmpty {
                spans.append(.text(raw))
            } else {
                spans.append(.citation(sourceIndices: indices, raw: raw))
            }
            cursor = range.upperBound
        }

        if cursor < answer.endIndex {
            spans.append(.text(String(answer[cursor...])))
        }
        if spans.isEmpty { spans = [.text(answer)] }

        return Result(spans: spans,
                      citedSourceIndices: cited.sorted(),
                      outOfRangeCitations: outOfRange,
                      literalURLs: SourceHarvester.bareURLs(in: answer))
    }
}
