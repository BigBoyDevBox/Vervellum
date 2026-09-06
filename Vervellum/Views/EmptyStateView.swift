import SwiftUI

/// What the panel shows before the first question.
///
/// Two states, and the difference matters: an app that is ready shows what it is for,
/// while an app that is missing its keys shows *only* that, with the fix one click
/// away. Mixing the two — a friendly welcome with a small warning at the bottom —
/// produces a first run where the user types a question and gets an error.
struct EmptyStateView: View {

    let isConfigured: Bool
    let summonShortcut: String
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PanelTheme.Space.large) {
            if isConfigured { ready } else { setup }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: PanelTheme.Space.medium) {
            Text("Ask a question.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PanelTheme.Palette.primaryText)
            Text("Vervellum plans web searches, runs them, then writes an answer that "
                 + "cites only what it found — and grades its own claims against that evidence.")
                .font(PanelTheme.Font.body(1.0))
                .foregroundStyle(PanelTheme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: PanelTheme.Space.tight) {
                hint("Return", "ask · Shift-Return for a new line")
                hint("/", "commands, including /direct for no search")
                hint("Esc", "clear the draft, then close")
                hint(summonShortcut, "summon or dismiss from anywhere")
            }
            .padding(.top, PanelTheme.Space.small)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: PanelTheme.Space.medium) {
            Label("Not configured yet", systemImage: "key")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PanelTheme.Palette.verdict(.mixed))
            Text("Vervellum needs two things: an OpenAI-compatible model endpoint, and a "
                 + "web-search key. Both stay on this Mac — the keys go in the Keychain, "
                 + "and nothing is sent anywhere except to the providers you name.")
                .font(PanelTheme.Font.body(1.0))
                .foregroundStyle(PanelTheme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(PanelTheme.Palette.accent)
        }
    }

    private func hint(_ key: String, _ meaning: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PanelTheme.Space.small) {
            Text(key)
                .font(PanelTheme.Font.citation(1.0))
                .foregroundStyle(PanelTheme.Palette.primaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(PanelTheme.Palette.chipFill,
                            in: RoundedRectangle(cornerRadius: PanelTheme.Radius.chip, style: .continuous))
            Text(meaning)
                .font(PanelTheme.Font.caption)
                .foregroundStyle(PanelTheme.Palette.tertiaryText)
            Spacer(minLength: 0)
        }
    }
}
