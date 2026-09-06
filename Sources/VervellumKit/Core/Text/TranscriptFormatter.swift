import Foundation

/// Renders a finished turn as plain text.
///
/// One formatter for two very different destinations — the macOS Copy button and the
/// Linux command line — because the hard part is not the layout, it is deciding what
/// must travel with the prose for it to still mean anything. Copying an answer whose
/// `[3]` markers point at nothing is worse than useless, so the cited sources come
/// with it; so do the verdicts, because an answer without them is exactly the
/// confident-sounding paragraph this app exists to replace.
///
/// Only *cited* sources are listed. A dump of everything the search happened to return
/// misrepresents what the answer actually rests on.
///
/// Pure and dependency-free, so it is fully unit-testable.
enum TranscriptFormatter {

    static func plainText(_ turn: ResearchTurn) -> String {
        var lines: [String] = [turn.question, ""]

        if let failure = turn.failure {
            lines.append("Failed: " + failure)
            return lines.joined(separator: "\n")
        }

        lines.append(turn.answer)

        if !turn.findings.isEmpty {
            lines.append("")
            lines.append("Claims")
            for finding in turn.findings {
                let citation = finding.sourceNumbers.isEmpty
                    ? ""
                    : " [" + finding.sourceNumbers.map(String.init).joined(separator: ",") + "]"
                lines.append("- \(finding.verdict.label.uppercased())\(citation): \(finding.claim)")
                if !finding.reasoning.isEmpty { lines.append("  \(finding.reasoning)") }
            }
        }

        let cited = turn.citedSources(
            using: CitationValidator.validate(answer: turn.answer, sourceCount: turn.sources.count))
        if !cited.isEmpty {
            lines.append("")
            lines.append("Sources")
            lines.append(contentsOf: cited.map { "[\($0.number)] \($0.title) — \($0.url)" })
        }

        if !turn.limitations.isEmpty {
            lines.append("")
            lines.append("Limitations: " + turn.limitations)
        }

        for notice in turn.notices {
            lines.append("")
            lines.append("Note: " + notice.message)
        }

        return lines.joined(separator: "\n")
    }
}
