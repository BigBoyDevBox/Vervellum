import SwiftUI
import AppKit

/// The two global shortcuts.
///
/// Both are recorded rather than typed: a shortcut is a key code plus modifier bits,
/// and asking a user to describe one in text produces a field that cannot express
/// their keyboard layout. `HotkeyRecorder` captures the real event.
struct ShortcutsView: View {

    @ObservedObject var preferences: Preferences
    var onChanged: () -> Void

    @State private var summon = HotkeyBinding.defaultSummon
    @State private var selection = HotkeyBinding.defaultResearchSelection
    @State private var isAccessibilityAuthorized = SelectedTextReader.isAuthorized

    var body: some View {
        SettingsPane {
            SettingsSection(
                title: "Summon",
                footnote: "Works from any app, including over a full-screen window. Press it again "
                    + "to dismiss the panel, or — on a second display — to move it to the screen "
                    + "your pointer is on. Vervellum needs no permission for this: the shortcut "
                    + "uses the system's own hotkey registration, not a keyboard monitor.") {
                shortcutRow(binding: $summon, label: "Ask Vervellum") { preferences.summonHotkey = $0 }
            }

            SettingsSection(
                title: "Research the selection",
                footnote: "Summons the panel with whatever text is selected in the app you were "
                    + "using already in the composer. This is the one feature that needs "
                    + "Accessibility, so it is off until you turn it on.") {
                shortcutRow(binding: $selection, label: "Research selection") {
                    preferences.researchSelectionHotkey = $0
                }
                Toggle("Remove credential-shaped text from the selection", isOn: Binding(
                    get: { preferences.redactSecrets },
                    set: { preferences.redactSecrets = $0 }))
                Text("Catches API keys, tokens, private-key blocks and KEY=value lines before "
                     + "they reach the composer, and says how many it removed. It is a safety "
                     + "net, not a guarantee — a password that looks like an ordinary word will "
                     + "pass straight through, so read what you are about to send.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                accessibilityRow
            }
        }
        .onAppear {
            summon = preferences.summonHotkey
            selection = preferences.researchSelectionHotkey
            isAccessibilityAuthorized = SelectedTextReader.isAuthorized
        }
    }

    private func shortcutRow(binding: Binding<HotkeyBinding>,
                             label: String,
                             apply: @escaping (HotkeyBinding) -> Void) -> some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Toggle("Enabled", isOn: Binding(
                    get: { binding.wrappedValue.enabled },
                    set: { enabled in
                        var updated = binding.wrappedValue
                        updated.enabled = enabled
                        binding.wrappedValue = updated
                        apply(updated)
                        onChanged()
                    }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                HotkeyRecorder(binding: Binding(
                    get: { binding.wrappedValue },
                    set: { updated in
                        binding.wrappedValue = updated
                        apply(updated)
                        onChanged()
                    }))
                    .frame(width: 150, height: 22)
                    .disabled(!binding.wrappedValue.enabled)
            }
        }
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        HStack(spacing: 8) {
            Image(systemName: isAccessibilityAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isAccessibilityAuthorized ? Color.green : Color.orange)
            Text(isAccessibilityAuthorized
                 ? "Accessibility is granted."
                 : "Accessibility is not granted — this shortcut will explain and offer to open Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(isAccessibilityAuthorized ? "Review…" : "Grant…") {
                // Ask first, open second. The system prompt appears at most once per
                // app per machine, so a user who has never seen it gets the one-click
                // path; everyone else gets the pane, where the app is already listed.
                SelectedTextReader.requestAuthorization()
                SelectedTextReader.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        // The grant is made in System Settings, so this row only learns about it when
        // the user comes back — there is no notification for a TCC change.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityAuthorized = SelectedTextReader.isAuthorized
        }
    }
}
