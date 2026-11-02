import Foundation

/// Whether a turn still has a first draft worth comparing with the answer on screen.
///
/// The revision and regather notices say the draft is kept for comparison. Offering
/// it only when it differs from the answer avoids a disclosure that opens onto the
/// same prose.
enum DraftComparison {
    static let showLabel = "Show the first draft"
    static let hideLabel = "Hide the first draft"

    static func isOffered(draft: String?, answer: String) -> Bool {
        guard let draft else { return false }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
