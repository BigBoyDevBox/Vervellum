import SwiftUI
import AppKit

/// The panel's design tokens.
///
/// One file, no magic numbers anywhere else. A research panel is dense — a question,
/// a process trail, prose, a verdict table, a source list and a composer all inside
/// 460 points — so consistency is not an aesthetic preference here, it is what keeps
/// the density readable.
///
/// Three rules the palette follows:
///
/// * **Meaning is never carried by colour alone.** Every verdict pairs its colour
///   with a distinct SF Symbol and a text label, so the table survives colour-blind
///   vision, a dimmed display, and a screenshot in a bug report.
/// * **Text colour comes from the semantic set**, so it tracks the user's appearance,
///   Increase Contrast, and Reduce Transparency settings without special-casing.
/// * **Glass is never nested.** The panel background is glass; everything inside it
///   is a flat translucent fill. Layering glass on glass produces mud and costs a
///   render pass per layer.
enum PanelTheme {

    // MARK: Spacing

    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let section: CGFloat = 20
        /// Horizontal padding of the content column.
        static let gutter: CGFloat = 16
    }

    // MARK: Shape

    enum Radius {
        static let chip: CGFloat = 5
        static let card: CGFloat = 9
        static let panel: CGFloat = 14
    }

    // MARK: Type

    enum Font {
        static func body(_ scale: Double) -> SwiftUI.Font { .system(size: 13 * scale) }
        static func bodyEmphasis(_ scale: Double) -> SwiftUI.Font { .system(size: 13 * scale, weight: .semibold) }
        static func heading(_ level: Int, _ scale: Double) -> SwiftUI.Font {
            switch level {
            case 1: return .system(size: 16 * scale, weight: .semibold)
            case 2: return .system(size: 14.5 * scale, weight: .semibold)
            default: return .system(size: 13 * scale, weight: .semibold)
            }
        }
        static func code(_ scale: Double) -> SwiftUI.Font {
            .system(size: 11.5 * scale, design: .monospaced)
        }
        static func citation(_ scale: Double) -> SwiftUI.Font {
            .system(size: 10.5 * scale, weight: .medium, design: .monospaced)
        }
        /// Section labels: small, uppercase, tracked out.
        static let label: SwiftUI.Font = .system(size: 10, weight: .semibold)
        static let caption: SwiftUI.Font = .system(size: 11)
        static let question: SwiftUI.Font = .system(size: 13.5, weight: .medium)
    }

    // MARK: Colour

    enum Palette {
        static let accent = Color(red: 1.0, green: 0.541, blue: 0.298)

        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let tertiaryText = Color.secondary.opacity(0.62)

        /// Flat fills for cards and chips. Deliberately not materials: see the note
        /// about nesting glass in this type's documentation.
        static let cardFill = Color.primary.opacity(0.05)
        static let chipFill = Color.primary.opacity(0.075)
        static let hairline = Color.primary.opacity(0.11)

        /// A legibility scrim behind the content column. Liquid Glass over an
        /// arbitrary desktop — a photo, a bright IDE, a video — cannot be relied on to
        /// keep 13pt text readable, and the system does not add one for you.
        static let scrim = Color.black.opacity(0.16)

        static func verdict(_ verdict: Verdict) -> Color {
            switch verdict {
            case .supported: return Color(red: 0.20, green: 0.68, blue: 0.42)
            case .contradicted: return Color(red: 0.88, green: 0.30, blue: 0.30)
            case .mixed: return Color(red: 0.92, green: 0.66, blue: 0.20)
            case .insufficient: return Color(red: 0.47, green: 0.55, blue: 0.68)
            case .opinion: return Color(red: 0.60, green: 0.50, blue: 0.85)
            }
        }
    }

    // MARK: Motion

    enum Motion {
        /// Streaming text must not animate its own layout — the answer would shiver
        /// on every token. Only discrete state changes (a stage completing, a section
        /// expanding) animate.
        static let stage: Animation = .easeOut(duration: 0.18)
        static let disclosure: Animation = .easeInOut(duration: 0.16)
    }
}

/// The panel's background: Liquid Glass on macOS 26, a blurred `NSVisualEffectView`
/// below it, and in both cases a legibility scrim.
///
/// The scrim is not optional. Glass takes its colour from whatever is behind the
/// window, and "whatever is behind the window" is the user's entire desktop — so
/// without a scrim the same 13pt paragraph is crisp over a dark editor and unreadable
/// over a bright photo.
struct PanelBackground: View {
    var cornerRadius: CGFloat = PanelTheme.Radius.panel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if #available(macOS 26.0, *), !reduceTransparency {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
            }
            shape.fill(PanelTheme.Palette.scrim)
            shape.strokeBorder(PanelTheme.Palette.hairline, lineWidth: 0.5)
        }
    }

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
