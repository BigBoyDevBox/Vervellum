import Foundation

/// Turns the command line words after a research flag into one usable question.
///
/// Kept in Core so the headless front end cannot drift from the GUI's central rule:
/// whitespace is not a question and must be rejected before a provider call is built.
enum CLIQuestion {

    static func joined<Arguments: Sequence>(_ arguments: Arguments) -> String?
    where Arguments.Element == String {
        let question = arguments.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return question.isEmpty ? nil : question
    }
}
