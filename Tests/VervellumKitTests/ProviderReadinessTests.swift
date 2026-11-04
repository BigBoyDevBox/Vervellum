import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class ProviderReadinessTests: XCTestCase {

    private final class RecordingSecrets: SecretStore {
        var reads: [SecretAccount] = []
        var backendDescription: String { "test store" }

        func value(for account: SecretAccount) -> String? {
            reads.append(account)
            return nil
        }

        func set(_ secret: String, for account: SecretAccount) throws {}
        func delete(_ account: SecretAccount) throws {}
    }

    func testNoSearchReadinessDoesNotRequireASearchCredential() {
        let settings = ProviderSettings(modelEndpoint: "http://localhost:11434/v1",
                                        modelName: "local")
        let secrets = EphemeralSecretStore()

        XCTAssertTrue(ProviderReadiness.problems(settings: settings, level: .direct,
                                                 secrets: secrets).isEmpty)
        XCTAssertEqual(ProviderReadiness.problems(settings: settings, level: .research,
                                                  secrets: secrets),
                       ["The web-search key is missing."])
    }

    func testNoSearchReadinessDoesNotReadTheSearchCredential() {
        let settings = ProviderSettings(modelEndpoint: "http://localhost:11434/v1",
                                        modelName: "local")
        let secrets = RecordingSecrets()

        _ = ProviderReadiness.problems(settings: settings, level: .direct, secrets: secrets)

        XCTAssertTrue(secrets.reads.isEmpty)
    }

    func testKeylessSearchBackendReadinessDoesNotReadCredentials() {
        let settings = ProviderSettings(modelEndpoint: "http://localhost:11434/v1",
                                        modelName: "local",
                                        searchEndpoint: "https://search.example",
                                        searchKind: .searxng)
        let secrets = RecordingSecrets()

        XCTAssertTrue(ProviderReadiness.problems(settings: settings, level: .research,
                                                 secrets: secrets).isEmpty)
        XCTAssertTrue(secrets.reads.isEmpty)
    }
}
