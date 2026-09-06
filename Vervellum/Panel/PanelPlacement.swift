import Foundation
import CoreGraphics

/// Where the panel sits on a screen.
enum PanelSide: String, Codable, CaseIterable, Identifiable {
    case leading
    case trailing
    case center

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leading: return "Left edge"
        case .trailing: return "Right edge"
        case .center: return "Centered"
        }
    }
}

/// Pure geometry for the research panel.
///
/// Kept free of AppKit so it is unit-testable: window placement is exactly the kind
/// of code that is wrong on a second display, wrong under a notch, and impossible to
/// verify by hand on every configuration.
///
/// Two rules drive the maths:
///
/// * **Never overlap the menu bar or the Dock.** All arithmetic is against
///   `visibleFrame`, never `frame`.
/// * **Never fall off a screen.** The result is clamped into the visible frame after
///   every other rule has had its say, so a stale remembered width from a 6K display
///   cannot strand the panel off the edge of a laptop screen.
enum PanelPlacement {

    /// Width limits. Below the minimum a cited paragraph wraps every few words;
    /// above the maximum the panel stops reading as an overlay and starts covering
    /// the work the user is asking about.
    static let minimumWidth: CGFloat = 360
    static let maximumWidth: CGFloat = 760
    static let defaultWidth: CGFloat = 460

    /// Height limits for the centered layout, which does not fill the screen.
    static let minimumHeight: CGFloat = 320
    static let defaultCenteredHeight: CGFloat = 620

    /// Gap between the panel and the edges of the visible area.
    static let margin: CGFloat = 12

    /// The panel's frame on `visibleFrame`.
    ///
    /// - Parameters:
    ///   - width: the user's preferred width, clamped here rather than at the call site.
    ///   - height: preferred height; used only by `.center` (edge layouts fill).
    static func frame(in visibleFrame: CGRect,
                      side: PanelSide,
                      width: CGFloat = defaultWidth,
                      height: CGFloat = defaultCenteredHeight) -> CGRect {
        let available = visibleFrame.insetBy(dx: margin, dy: margin)
        // A screen small enough that the margins would invert (or a zero-size frame
        // from a display waking up) must not produce a negative-size window.
        guard available.width > 0, available.height > 0 else { return visibleFrame }

        let panelWidth = min(max(width, minimumWidth), min(maximumWidth, available.width))

        switch side {
        case .leading, .trailing:
            let panelHeight = available.height
            let x = side == .leading ? available.minX : available.maxX - panelWidth
            return CGRect(x: x, y: available.minY, width: panelWidth, height: panelHeight)

        case .center:
            let panelHeight = min(max(height, minimumHeight), available.height)
            let x = available.midX - panelWidth / 2
            // Sit above centre — the Spotlight position. A centred panel puts the
            // composer, which is at the bottom, uncomfortably low on a tall display.
            let idealY = available.midY - panelHeight / 2 + available.height * 0.08
            let y = min(max(idealY, available.minY), available.maxY - panelHeight)
            return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
        }
    }

    /// The frame the panel animates *from* when appearing (and to when leaving): the
    /// final frame nudged off its anchoring edge, so the motion reads as the panel
    /// sliding in from the side it lives on rather than materialising in place.
    static func entryFrame(for frame: CGRect, side: PanelSide) -> CGRect {
        switch side {
        case .leading:  return frame.offsetBy(dx: -frame.width * 0.16, dy: 0)
        case .trailing: return frame.offsetBy(dx: frame.width * 0.16, dy: 0)
        case .center:   return frame.offsetBy(dx: 0, dy: -18)
        }
    }
}
