import SwiftUI

/// Where the two providers are configured.
///
/// The key fields follow one rule borrowed from every credential form that gets this
/// right: **a blank field means "keep what is stored", never "erase it"**. A user who
/// opens Settings to change the model name must not silently wipe their keys by
/// saving a form whose password fields rendered empty. Clearing is a separate,
/// explicit button.
struct ProvidersView: View {

    @ObservedObject var preferences: Preferences

    /// Typed as the shared protocol so this pane is one rename away from being
    /// reusable, and so it can say which backend is in use rather than assuming.
    private let keychain: SecretStore = KeychainStore()

    @State private var modelEndpoint = ""
    @State private var modelName = ""
    @State private var searchEndpoint = ""
    @State private var modelKeyEntry = ""
    @State private var searchKeyEntry = ""
    @State private var hasModelKey = false
    @State private var hasSearchKey = false
    @State private var status: String?
    @State private var statusIsProblem = false

    var body: some View {
        SettingsPane {
            SettingsSection(
                title: "Model",
                footnote: "Any OpenAI-compatible Chat Completions endpoint. A bare host or a "
                    + "versioned base such as /v1 gets /chat/completions appended; a full path is "
                    + "used as typed. HTTPS is required, except for a model server on localhost.") {
                LabeledContent("Endpoint") {
                    TextField("https://api.example.com/v1", text: $modelEndpoint)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Model") {
                    TextField("model-name", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                }
                keyRow(title: "API key",
                       entry: $modelKeyEntry,
                       hasStored: hasModelKey,
                       note: "Optional — a local model server usually needs none.") {
                    clear(SecretAccount.modelAPIKey)
                }
            }

            SettingsSection(
                title: "Web search",
                footnote: "Vervellum searches through a Model Context Protocol server. The default "
                    + "is z.ai's hosted web-search endpoint, which needs a Coding Plan key.") {
                LabeledContent("Endpoint") {
                    TextField(ProviderSettings.defaultSearchEndpoint, text: $searchEndpoint)
                        .textFieldStyle(.roundedBorder)
                }
                keyRow(title: "Search key",
                       entry: $searchKeyEntry,
                       hasStored: hasSearchKey,
                       note: "Required. Research cannot run without it.") {
                    clear(SecretAccount.searchAPIKey)
                }
            }

            HStack {
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                if let status {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(statusIsProblem ? Color.red : Color.secondary)
                }
                Spacer()
            }

            SettingsSection(title: "Where the keys live",
                            footnote: "Keys are stored in \(keychain.backendDescription), never in "
                                + "Vervellum's preferences file and never in a thread. They are sent "
                                + "only to the endpoints above, over HTTPS, and Vervellum never "
                                + "follows a redirect with a key attached.") { EmptyView() }
        }
        .onAppear(perform: load)
    }

    // MARK: Rows

    @ViewBuilder
    private func keyRow(title: String,
                        entry: Binding<String>,
                        hasStored: Bool,
                        note: String,
                        onClear: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    SecureField(hasStored ? "Stored — type to replace" : "Paste your key",
                                text: entry)
                        .textFieldStyle(.roundedBorder)
                    if hasStored {
                        Button("Clear", action: onClear)
                            .help("Remove the stored key from the Keychain")
                    }
                }
                Text(hasStored ? "A key is stored. \(note)" : note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Actions

    private func load() {
        let settings = preferences.providerSettings
        modelEndpoint = settings.modelEndpoint
        modelName = settings.modelName
        searchEndpoint = settings.searchEndpoint
        hasModelKey = keychain.hasValue(for: SecretAccount.modelAPIKey)
        hasSearchKey = keychain.hasValue(for: SecretAccount.searchAPIKey)
    }

    private func save() {
        preferences.providerSettings = ProviderSettings(modelEndpoint: modelEndpoint,
                                                        modelName: modelName,
                                                        searchEndpoint: searchEndpoint)
        do {
            // Blank means "leave the stored key alone" — see the type's documentation.
            // The check trims first, because `KeychainStore.set` trims too and *deletes*
            // on an empty result: a field holding one stray space from a sloppy paste
            // would otherwise pass `!isEmpty` and wipe a working key, reporting "Saved."
            if !modelKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try keychain.set(modelKeyEntry, for: SecretAccount.modelAPIKey)
            }
            modelKeyEntry = ""
            if !searchKeyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try keychain.set(searchKeyEntry, for: SecretAccount.searchAPIKey)
            }
            searchKeyEntry = ""
        } catch {
            status = error.localizedDescription
            statusIsProblem = true
            return
        }
        // Read the Keychain directly rather than through the `@State` flags `load()`
        // just wrote: a SwiftUI state write is a store for the *next* update, and
        // reading it back on the same call stack is not a documented guarantee. Getting
        // it wrong would report "The web-search key is missing." on the very save that
        // supplied it.
        let modelKeyPresent = keychain.hasValue(for: SecretAccount.modelAPIKey)
        let searchKeyPresent = keychain.hasValue(for: SecretAccount.searchAPIKey)
        hasModelKey = modelKeyPresent
        hasSearchKey = searchKeyPresent

        // Report configuration problems now rather than at the first question, but do
        // not try to reach the providers: a connectivity check here would cost a
        // request and still not prove the key works for the model that was named.
        let problems = preferences.providerSettings.problems(hasModelKey: modelKeyPresent,
                                                             hasSearchKey: searchKeyPresent)
        statusIsProblem = !problems.isEmpty
        status = problems.isEmpty ? "Saved." : problems.joined(separator: " ")
    }

    private func clear(_ account: SecretAccount) {
        try? keychain.delete(account)
        // Only the key flags are refreshed. A full `load()` would also overwrite the
        // endpoint and model fields, throwing away edits the user had typed but not yet
        // saved — a surprising amount of work to lose to a Clear button.
        hasModelKey = keychain.hasValue(for: .modelAPIKey)
        hasSearchKey = keychain.hasValue(for: .searchAPIKey)
        statusIsProblem = false
        status = "Key removed."
    }
}
