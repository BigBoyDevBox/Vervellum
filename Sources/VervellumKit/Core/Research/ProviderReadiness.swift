/// One front-end-neutral readiness check. The selected research level decides whether
/// search configuration is relevant; keeping that rule here prevents a panel from
/// disagreeing with the runner that will actually accept the question.
enum ProviderReadiness {

    static func problems(settings: ProviderSettings,
                         level: ResearchLevel,
                         secrets: SecretStore) -> [String] {
        let requiresSearch = level.searches
        let requiresSearchKey = requiresSearch && settings.searchKind.requiresKey
        // Model keys are deliberately optional, as are credentials for SearXNG and the
        // Kagi CLI. Do not turn a readiness refresh into an unnecessary keyring prompt.
        return settings.problems(hasModelKey: false,
                                 hasSearchKey: requiresSearchKey
                                    ? secrets.hasSearchKey(for: settings) : false,
                                 requiresSearch: requiresSearch)
    }
}
