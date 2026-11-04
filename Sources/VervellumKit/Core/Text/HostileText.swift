import Foundation

/// Strips the characters a hostile or broken page can use to make the panel display
/// something other than what was read.
///
/// Two families, each with a concrete failure rather than a vague "unusual":
///
/// * Bidi formatting characters (RLO `U+202E`, the isolates `U+2066`–`U+2069`, …)
///   reorder a line, so a source title can read "trustworthy" to the eye while the
///   model saw it scrambled — or the other way round. They are invisible, which is
///   what makes them an attack rather than a typo.
/// * C0 and C1 controls and DEL. A NUL truncates a GTK C string mid-title, because
///   GTK labels are C strings underneath; the rest are terminal plumbing from when
///   text was a terminal — C1's NEL and single-shifts included, which a page can
///   still smuggle in through a numeric character reference (`&#x85;`).
///
/// Tab and newline are C0 controls but are kept: newline is how the page extractor
/// marks block boundaries (see `HTMLTextExtractor.normalize`), and dropping it would
/// merge paragraphs into misquotations. Carriage returns are normalized to newlines
/// first, so a page that ends lines the Windows way keeps its breaks.
enum HostileText {

    /// The Unicode bidi formatting characters: marks, embeddings, overrides and
    /// isolates, with their pops. Complete per Unicode 15 `Bidi_Control`.
    private static let bidiControls: Set<Unicode.Scalar> = [
        "\u{061C}",  // Arabic letter mark
        "\u{200E}", "\u{200F}",                              // LRM, RLM
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",  // LRE, RLE, PDF, LRO, RLO
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",      // LRI, RLI, FSI, PDI
    ]

    private static func isDropped(_ scalar: Unicode.Scalar) -> Bool {
        bidiControls.contains(scalar)
            || (scalar.value <= 0x1F && scalar != "\t" && scalar != "\n")
            || scalar.value == 0x7F
            || (0x80...0x9F).contains(scalar.value)
    }

    /// The text without those characters. The words around them are untouched —
    /// stripping the override is not a licence to drop the sentence it sat in.
    static func stripped(_ text: String) -> String {
        // `\r\n` collapses to one `\n` before lone `\r` is handled, so a CRLF pair
        // doesn't become two breaks and a classic-Mac `\r` isn't dropped as C0.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result = String.UnicodeScalarView()
        result.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars where !isDropped(scalar) {
            result.append(scalar)
        }
        return String(result)
    }
}
