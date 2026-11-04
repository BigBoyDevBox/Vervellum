import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class ProviderCredentialCommitTests: XCTestCase {

    private let modelID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let searchID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let oldModel = SecretAccount(rawValue: "old-model")
    private let oldSearch = SecretAccount(rawValue: "old-search")
    private let freshModel = SecretAccount(rawValue: "fresh-model")
    private let freshSearch = SecretAccount(rawValue: "fresh-search")

    func testReplacementIsStagedBeforeSettingsAndOldAccountIsDeletedAfterward() throws {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([oldModel: "old key"])
        var events: [String] = []
        secrets.onOperation = { events.append($0) }
        var persisted: ProviderSettings?

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(model: [modelID: .replace(" new key ")]),
            secrets: secrets,
            makeAccount: { _ in self.freshModel }) { settings in
                events.append("persist")
                persisted = settings
            }

        XCTAssertEqual(result.settings.modelProfiles[0].secretAccount, freshModel)
        XCTAssertEqual(persisted, result.settings)
        XCTAssertEqual(secrets.value(for: freshModel), "new key")
        XCTAssertNil(secrets.value(for: oldModel))
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "set:fresh-model")),
                          try XCTUnwrap(events.firstIndex(of: "persist")))
        XCTAssertGreaterThan(try XCTUnwrap(events.firstIndex(of: "delete:old-model")),
                             try XCTUnwrap(events.firstIndex(of: "persist")))
    }

    func testStagingFailureLeavesOldEndpointAndCredentialPaired() {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([oldModel: "old key"])
        secrets.failSet.insert(freshModel)
        var persisted = false

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(model: [modelID: .replace("new key")]),
            secrets: secrets,
            makeAccount: { _ in self.freshModel }) { _ in
                persisted = true
            })

        XCTAssertFalse(persisted)
        XCTAssertEqual(secrets.value(for: oldModel), "old key")
    }

    func testDestinationChangeWithoutReplacementCommitsAFreshEmptyAccount() throws {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([oldModel: "old key"])
        var persisted: ProviderSettings?

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in self.freshModel }) { persisted = $0 }

        XCTAssertEqual(result.settings.modelProfiles[0].secretAccount, freshModel)
        XCTAssertEqual(persisted?.modelProfiles[0].endpoint, "https://new.example/v1")
        XCTAssertNil(secrets.value(for: freshModel))
        XCTAssertNil(secrets.value(for: oldModel))
        XCTAssertFalse(secrets.operations.contains("set:fresh-model"))
        XCTAssertTrue(secrets.operations.contains("delete:fresh-model"),
                      "an unreadable orphan must be cleared before the account is referenced")
    }

    func testUnchangedCanonicalDestinationKeepsItsAccount() throws {
        let original = settings(modelEndpoint: "https://EXAMPLE.com/v1/")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://example.com/v1"
        let secrets = RecordingSecretStore([oldModel: "old key"])

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in XCTFail("equivalent destinations must not rotate"); return self.freshModel },
            persist: { _ in })

        XCTAssertEqual(result.settings.modelProfiles[0].secretAccount, oldModel)
        XCTAssertFalse(secrets.operations.contains("set:fresh-model"))
        XCTAssertFalse(secrets.operations.contains("delete:old-model"))
    }

    func testExplicitClearRotatesRatherThanMutatingAReferencedAccount() throws {
        let original = settings()
        let secrets = RecordingSecretStore([oldModel: "old key"])

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(model: [modelID: .clear]),
            secrets: secrets,
            makeAccount: { _ in self.freshModel },
            persist: { _ in })

        XCTAssertEqual(result.settings.modelProfiles[0].secretAccount, freshModel)
        XCTAssertNil(secrets.value(for: oldModel))
        XCTAssertNil(secrets.value(for: freshModel))
    }

    func testSearchKindChangeRotatesEvenWhenTheFieldTextIsUnchanged() throws {
        let original = settings(searchKind: .mcp, searchEndpoint: "https://search.example/api")
        var edited = original
        edited.searchProfiles[0].kind = .searxng
        let secrets = RecordingSecretStore([oldSearch: "search key"])

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in self.freshSearch },
            persist: { _ in })

        XCTAssertEqual(result.settings.searchProfiles[0].secretAccount, freshSearch)
        XCTAssertNil(secrets.value(for: oldSearch))
    }

    func testDifferentInvalidDestinationsRotateConservatively() throws {
        let original = settings(modelEndpoint: "not a url")
        var edited = original
        edited.modelProfiles[0].endpoint = "still not a url"

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: RecordingSecretStore(),
            makeAccount: { _ in self.freshModel },
            persist: { _ in })

        XCTAssertEqual(result.settings.modelProfiles[0].secretAccount, freshModel)
    }

    func testAccountSharedByASurvivingProfileIsNotDeleted() throws {
        let secondID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        var original = settings()
        original.modelProfiles.append(ModelProfile(
            id: secondID, name: "second", endpoint: "https://second.example/v1",
            model: "model", keyAccount: oldModel.rawValue))
        var edited = original
        edited.modelProfiles.removeAll { $0.id == modelID }
        edited.selectedModelID = secondID
        let secrets = RecordingSecretStore([oldModel: "shared"])

        _ = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in XCTFail("surviving profile keeps its account"); return self.freshModel },
            persist: { _ in })

        XCTAssertEqual(secrets.value(for: oldModel), "shared")
        XCTAssertFalse(secrets.operations.contains("delete:old-model"))
    }

    func testCleanupFailureDoesNotUndoCommittedSettings() throws {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([oldModel: "old key"])
        secrets.failDelete.insert(oldModel)
        var persisted: ProviderSettings?

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in self.freshModel }) { persisted = $0 }

        XCTAssertEqual(persisted, result.settings)
        XCTAssertEqual(result.cleanupFailures, [oldModel])
        XCTAssertEqual(result.settings.modelProfiles[0].secretAccount, freshModel)
    }

    func testCleanupJournalSurvivesReconstructionAndRetries() throws {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([oldModel: "old key"])
        secrets.failDelete.insert(oldModel)
        var journal: [SecretAccount] = []

        let first = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in self.freshModel },
            pendingCleanup: journal,
            recordPendingCleanup: { journal = $0 },
            persist: { _ in })

        XCTAssertEqual(journal, [oldModel])
        secrets.failDelete.remove(oldModel)

        let second = try ProviderCredentialCommit.commit(
            original: first.settings,
            edited: first.settings,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in XCTFail("a cleanup retry must not rotate accounts"); return self.freshSearch },
            pendingCleanup: journal,
            recordPendingCleanup: { journal = $0 },
            persist: { _ in })

        XCTAssertTrue(second.cleanupFailures.isEmpty)
        XCTAssertTrue(journal.isEmpty)
        XCTAssertNil(secrets.value(for: oldModel))
    }

    func testAJournalledAccountCannotBeMintedForANewDestination() {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([freshModel: "orphaned old key"])
        var persisted = false

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in self.freshModel },
            pendingCleanup: [freshModel],
            persist: { _ in persisted = true })) { error in
                guard case ProviderCredentialCommit.CommitError.accountCollision = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }

        XCTAssertFalse(persisted)
        XCTAssertEqual(secrets.value(for: freshModel), "orphaned old key")
    }

    func testAnUnjournalledPopulatedAccountCannotBeMintedAfterACrash() {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([freshModel: "orphaned old key"])

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in self.freshModel },
            persist: { _ in XCTFail("a populated account must never become referenced") })) {
                error in
                guard case ProviderCredentialCommit.CommitError.accountCollision = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
    }

    func testEveryCommitRejectsDuplicateFixedAccountOwners() {
        let secondID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        var original = settings()
        original.modelProfiles[0].keyAccount = SecretAccount.modelAPIKey.rawValue
        original.modelProfiles.append(ModelProfile(
            id: secondID, name: "other", endpoint: "https://other.example/v1",
            model: "other", keyAccount: SecretAccount.modelAPIKey.rawValue))
        var persisted = false

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: RecordingSecretStore([.modelAPIKey: "shared key"]),
            persist: { _ in persisted = true })) { error in
                guard case ProviderCredentialCommit.CommitError.sharedLegacyAccount(.modelAPIKey)
                    = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }

        XCTAssertFalse(persisted)
    }

    func testEveryCommitRejectsDuplicateFixedSearchAccountOwners() {
        let secondID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        var original = settings()
        original.searchProfiles[0].keyAccount = SecretAccount.searchAPIKey.rawValue
        original.searchProfiles.append(SearchProfile(
            id: secondID, name: "other", kind: .searxng,
            endpoint: "https://other.example",
            keyAccount: SecretAccount.searchAPIKey.rawValue))

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: RecordingSecretStore([.searchAPIKey: "shared key"]),
            persist: { _ in XCTFail("ambiguous ownership must not persist") })) { error in
                guard case ProviderCredentialCommit.CommitError.sharedLegacyAccount(.searchAPIKey)
                    = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
    }

    func testAModelCannotOwnARecognizedSearchCredentialAccount() {
        var original = settings()
        original.modelProfiles[0].keyAccount = SecretAccount.searchAPIKey.rawValue

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: RecordingSecretStore([.searchAPIKey: "search key"]),
            persist: { _ in XCTFail("a cross-kind account must not persist") })) { error in
                guard case ProviderCredentialCommit.CommitError.credentialAccountMismatch(
                    .searchAPIKey) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
    }

    func testASearchProviderCannotOwnARecognizedModelCredentialAccount() {
        var original = settings()
        original.searchProfiles[0].keyAccount = SecretAccount.modelAPIKey.rawValue

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: RecordingSecretStore([.modelAPIKey: "model key"]),
            persist: { _ in XCTFail("a cross-kind account must not persist") })) { error in
                guard case ProviderCredentialCommit.CommitError.credentialAccountMismatch(
                    .modelAPIKey) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
    }

    func testRestoringAnExistingPointerCannotReintroduceACrossKindAccount() {
        var original = settings()
        original.modelProfiles[0].keyAccount = SecretAccount.searchAPIKey.rawValue
        var edited = original
        edited.modelProfiles[0].keyAccount = SecretAccount.modelAPIKey.rawValue

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: RecordingSecretStore([.searchAPIKey: "search key"]),
            persist: { _ in XCTFail("restored pointers require the same validation") })) { error in
                guard case ProviderCredentialCommit.CommitError.credentialAccountMismatch(
                    .searchAPIKey) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
    }

    func testFailedRollbackJournalsAStagedAccountAndRetriesItsDeletion() throws {
        let secondID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let oldSecond = SecretAccount(rawValue: "old-model-second")
        let freshSecond = SecretAccount(rawValue: "fresh-model-second")
        var original = settings(modelEndpoint: "https://old.example/v1")
        original.modelProfiles.append(ModelProfile(
            id: secondID, name: "second", endpoint: "https://old-second.example/v1",
            model: "second", keyAccount: oldSecond.rawValue))
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        edited.modelProfiles[1].endpoint = "https://new-second.example/v1"
        var accounts = [freshModel, freshSecond]
        let secrets = RecordingSecretStore()
        secrets.failSet.insert(freshSecond)
        secrets.failDelete.insert(freshModel)
        var journal: [SecretAccount] = []

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(model: [
                modelID: .replace("first replacement"),
                secondID: .replace("second replacement"),
            ]),
            secrets: secrets,
            makeAccount: { _ in accounts.removeFirst() },
            recordPendingCleanup: { journal = $0 },
            persist: { _ in XCTFail("staging failed before persistence") }))

        XCTAssertEqual(secrets.value(for: freshModel), "first replacement")
        XCTAssertTrue(journal.contains(freshModel),
                      "a rollback refusal must leave enough state for a later retry")

        secrets.failSet = []
        secrets.failDelete = []
        _ = try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in XCTFail("a cleanup retry must not mint an account"); return freshModel },
            pendingCleanup: journal,
            recordPendingCleanup: { journal = $0 },
            persist: { _ in })

        XCTAssertNil(secrets.value(for: freshModel))
        XCTAssertTrue(journal.isEmpty)
    }

    func testMintedAccountsAreDurablyJournalledBeforeTheFirstStagedWrite() throws {
        let original = settings(modelEndpoint: "https://old.example/v1")
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        var durableJournal: [SecretAccount] = []
        var journalAtCrash: [SecretAccount] = []
        var events: [String] = []
        let secrets = RecordingSecretStore()
        secrets.onOperation = { operation in
            events.append(operation)
            if operation == "set:fresh-model" { journalAtCrash = durableJournal }
        }

        _ = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(model: [modelID: .replace("replacement")]),
            secrets: secrets,
            makeAccount: { _ in self.freshModel },
            persistPendingCleanup: {
                events.append("persist-journal")
                durableJournal = $0
            },
            persist: { _ in events.append("persist-settings") })

        XCTAssertTrue(journalAtCrash.contains(freshModel))
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "persist-journal")),
                          try XCTUnwrap(events.firstIndex(of: "set:fresh-model")))

        // Restart at the checkpoint captured by `onOperation`: settings are still old,
        // the staged secret survived, and only the durable journal can discover it.
        let restartedSecrets = RecordingSecretStore([freshModel: "replacement"])
        var restartedJournal = journalAtCrash
        _ = try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: restartedSecrets,
            pendingCleanup: restartedJournal,
            persistPendingCleanup: { restartedJournal = $0 },
            recordPendingCleanup: { restartedJournal = $0 },
            persist: { _ in })

        XCTAssertNil(restartedSecrets.value(for: freshModel))
        XCTAssertTrue(restartedJournal.isEmpty)
    }

    func testFailedDurabilityBarrierPreventsFixedPostwriteAndRestartsFailClosed() throws {
        var original = settings(modelEndpoint: "https://old.example/v1")
        original.modelProfiles[0].keyAccount = SecretAccount.modelAPIKey.rawValue
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let store = VolatileSettingsStore()
        let preferences = CorePreferences(store: store)
        preferences.providerSettings = original
        store.synchronizeSucceeds = false
        store.events = []
        let secrets = RecordingSecretStore([.modelAPIKey: "old key"])
        secrets.onOperation = { store.events.append($0) }

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(model: [modelID: .replace("new key")]),
            secrets: secrets,
            makeAccount: { _ in self.freshModel },
            persist: { try preferences.persistProviderSettings($0) }))

        XCTAssertTrue(store.events.contains("synchronize"))
        XCTAssertFalse(store.events.contains("set:model-api-key"))
        XCTAssertNil(secrets.value(for: .modelAPIKey))
        let restarted = CorePreferences(store: store.restarted()).providerSettings
        XCTAssertEqual(restarted.modelEndpoint, "https://old.example/v1")
    }

    func testFixedPostwriteRunsOnlyAfterTheDurabilityBarrier() throws {
        var original = settings(modelEndpoint: "https://old.example/v1")
        original.modelProfiles[0].keyAccount = SecretAccount.modelAPIKey.rawValue
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let store = VolatileSettingsStore()
        let preferences = CorePreferences(store: store)
        preferences.providerSettings = original
        store.events = []
        let secrets = RecordingSecretStore([.modelAPIKey: "old key"])
        secrets.onOperation = { store.events.append($0) }

        _ = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(model: [modelID: .replace("new key")]),
            secrets: secrets,
            makeAccount: { _ in self.freshModel },
            persist: { try preferences.persistProviderSettings($0) })

        let barrier = try XCTUnwrap(store.events.firstIndex(of: "synchronize"))
        let postwrite = try XCTUnwrap(store.events.firstIndex(of: "set:model-api-key"))
        XCTAssertLessThan(barrier, postwrite)
        XCTAssertEqual(CorePreferences(store: store.restarted()).providerSettings.modelEndpoint,
                       "https://new.example/v1")
    }

    func testFixedModelAccountUsesDeletePersistSetBarrier() {
        var original = settings(modelEndpoint: "https://old.example/v1")
        original.modelProfiles[0].keyAccount = SecretAccount.modelAPIKey.rawValue
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new.example/v1"
        let secrets = RecordingSecretStore([.modelAPIKey: "old key"])
        secrets.failSet.insert(.modelAPIKey)
        var events: [String] = []
        secrets.onOperation = { events.append($0) }
        var persisted: ProviderSettings?

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(model: [modelID: .replace("new key")]),
            secrets: secrets,
            makeAccount: { _ in XCTFail("fixed account must use its barrier"); return self.freshModel }) {
                events.append("persist")
                persisted = $0
            })

        XCTAssertEqual(persisted?.modelProfiles[0].secretAccount, .modelAPIKey)
        XCTAssertEqual(persisted?.modelProfiles[0].endpoint, "https://new.example/v1")
        XCTAssertNil(secrets.value(for: .modelAPIKey))
        XCTAssertEqual(events.filter { $0 != "delete:search-api-key" },
                       ["delete:model-api-key", "persist", "set:model-api-key"])
    }

    func testFixedSearchAccountUsesDeletePersistSetBarrier() throws {
        var original = settings(searchKind: .mcp, searchEndpoint: "https://search.example/mcp")
        original.searchProfiles[0].keyAccount = SecretAccount.searchAPIKey.rawValue
        var edited = original
        edited.searchProfiles[0].kind = .searxng
        edited.searchProfiles[0].endpoint = "https://search.example"
        let secrets = RecordingSecretStore([.searchAPIKey: "old key"])
        var events: [String] = []
        secrets.onOperation = { events.append($0) }

        let result = try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(search: [searchID: .replace("new key")]),
            secrets: secrets,
            makeAccount: { _ in XCTFail("fixed account must use its barrier"); return self.freshSearch }) { _ in
                events.append("persist")
            }

        XCTAssertEqual(result.settings.searchProfiles[0].secretAccount, .searchAPIKey)
        XCTAssertEqual(secrets.value(for: .searchAPIKey), "new key")
        XCTAssertEqual(events.filter { $0 != "delete:model-api-key" },
                       ["delete:search-api-key", "persist", "set:search-api-key"])
    }

    func testUnownedFixedAccountsAreDeletedBeforeScalarFallbackCanPersist() throws {
        let original = settings()
        let secrets = RecordingSecretStore([
            .modelAPIKey: "orphaned model key",
            .searchAPIKey: "orphaned search key",
        ])
        var events: [String] = []
        secrets.onOperation = { events.append($0) }

        _ = try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: secrets,
            persist: { _ in events.append("persist") })

        let modelDelete = try XCTUnwrap(events.firstIndex(of: "delete:model-api-key"))
        let searchDelete = try XCTUnwrap(events.firstIndex(of: "delete:search-api-key"))
        let persist = try XCTUnwrap(events.firstIndex(of: "persist"))
        XCTAssertLessThan(modelDelete, persist)
        XCTAssertLessThan(searchDelete, persist)
        XCTAssertNil(secrets.value(for: .modelAPIKey))
        XCTAssertNil(secrets.value(for: .searchAPIKey))
    }

    func testUnownedFixedAccountDeletionFailurePreventsScalarPersistence() {
        let original = settings()
        let secrets = RecordingSecretStore([.modelAPIKey: "orphaned model key"])
        secrets.failDelete.insert(.modelAPIKey)
        var persisted = false

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: original,
            edits: .init(),
            secrets: secrets,
            persist: { _ in persisted = true }))

        XCTAssertFalse(persisted)
        XCTAssertEqual(secrets.value(for: .modelAPIKey), "orphaned model key")
    }

    func testLaterBarrierFailureCanLeaveAnEarlierFixedKeyAbsentButDoesNotPersist() {
        var original = settings(modelEndpoint: "https://old-model.example/v1",
                                searchEndpoint: "https://old-search.example/mcp")
        original.modelProfiles[0].keyAccount = SecretAccount.modelAPIKey.rawValue
        original.searchProfiles[0].keyAccount = SecretAccount.searchAPIKey.rawValue
        var edited = original
        edited.modelProfiles[0].endpoint = "https://new-model.example/v1"
        edited.searchProfiles[0].endpoint = "https://new-search.example/mcp"
        let secrets = RecordingSecretStore([
            .modelAPIKey: "old model key",
            .searchAPIKey: "old search key",
        ])
        secrets.failDelete.insert(.searchAPIKey)
        var persisted = false

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in XCTFail("fixed accounts must use barriers"); return self.freshModel }) {
                _ in persisted = true
            })

        XCTAssertFalse(persisted)
        XCTAssertNil(secrets.value(for: .modelAPIKey),
                     "an earlier successful barrier is safely absent, not rolled back")
        XCTAssertEqual(secrets.value(for: .searchAPIKey), "old search key")
    }

    func testReaderDeletionFailurePreventsEndpointCommit() {
        let original = settings(readerEndpoint: "https://old.example/reader")
        var edited = original
        edited.readerEndpoint = "https://new.example/reader"
        let secrets = RecordingSecretStore([.readerAPIKey: "old reader key"])
        secrets.failDelete.insert(.readerAPIKey)
        var persisted = false

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(),
            secrets: secrets,
            makeAccount: { _ in self.freshModel }) { _ in persisted = true })

        XCTAssertFalse(persisted)
        XCTAssertEqual(secrets.value(for: .readerAPIKey), "old reader key")
    }

    func testReaderReplacementRunsDeletePersistSetAndCannotCarryTheOldKeyForward() {
        let original = settings(readerEndpoint: "https://old.example/reader")
        var edited = original
        edited.readerEndpoint = "https://new.example/reader"
        let secrets = RecordingSecretStore([.readerAPIKey: "old reader key"])
        secrets.failSet.insert(.readerAPIKey)
        var events: [String] = []
        secrets.onOperation = { events.append($0) }
        var persisted: ProviderSettings?

        XCTAssertThrowsError(try ProviderCredentialCommit.commit(
            original: original,
            edited: edited,
            edits: .init(reader: .replace("new reader key")),
            secrets: secrets,
            makeAccount: { _ in self.freshModel }) {
                events.append("persist")
                persisted = $0
            })

        XCTAssertEqual(persisted?.readerEndpoint, "https://new.example/reader")
        XCTAssertNil(secrets.value(for: .readerAPIKey))
        XCTAssertEqual(events.filter {
            $0 != "delete:model-api-key" && $0 != "delete:search-api-key"
        }, ["delete:reader-api-key", "persist", "set:reader-api-key"])
    }

    private func settings(modelEndpoint: String = "https://model.example/v1",
                          searchKind: SearchProviderKind = .mcp,
                          searchEndpoint: String = "https://search.example/mcp",
                          readerEndpoint: String = "https://reader.example/mcp") -> ProviderSettings {
        ProviderSettings(
            modelProfiles: [ModelProfile(
                id: modelID, name: "model", endpoint: modelEndpoint, model: "example-model",
                keyAccount: oldModel.rawValue)],
            selectedModelID: modelID,
            searchProfiles: [SearchProfile(
                id: searchID, name: "search", kind: searchKind, endpoint: searchEndpoint,
                keyAccount: oldSearch.rawValue)],
            selectedSearchID: searchID,
            readerEndpoint: readerEndpoint)
    }
}

private final class RecordingSecretStore: SecretStore {
    enum Failure: Error { case requested }

    private var values: [SecretAccount: String]
    var operations: [String] = []
    var failSet: Set<SecretAccount> = []
    var failDelete: Set<SecretAccount> = []
    var onOperation: ((String) -> Void)?

    init(_ values: [SecretAccount: String] = [:]) { self.values = values }

    var backendDescription: String { "test store" }

    func value(for account: SecretAccount) -> String? { values[account] }

    func set(_ secret: String, for account: SecretAccount) throws {
        record("set:\(account.rawValue)")
        if failSet.contains(account) { throw Failure.requested }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        values[account] = trimmed.isEmpty ? nil : trimmed
    }

    func delete(_ account: SecretAccount) throws {
        record("delete:\(account.rawValue)")
        if failDelete.contains(account) { throw Failure.requested }
        values[account] = nil
    }

    private func record(_ operation: String) {
        operations.append(operation)
        onOperation?(operation)
    }
}

/// Models the only distinction that matters across a process crash: writes visible to
/// this process versus bytes a fresh process can actually read.
private final class VolatileSettingsStore: SettingsStore {
    private var volatile: [String: Any]
    private var durable: [String: Any]
    var synchronizeSucceeds = true
    var events: [String] = []

    init(durable: [String: Any] = [:]) {
        self.durable = durable
        volatile = durable
    }

    func string(for key: String) -> String? { volatile[key] as? String }
    func double(for key: String) -> Double? { volatile[key] as? Double }
    func bool(for key: String) -> Bool? { volatile[key] as? Bool }

    func setString(_ value: String?, for key: String) { set(value, for: key) }
    func setDouble(_ value: Double?, for key: String) { set(value, for: key) }
    func setBool(_ value: Bool?, for key: String) { set(value, for: key) }

    func synchronize() -> Bool {
        events.append("synchronize")
        guard synchronizeSucceeds else { return false }
        durable = volatile
        return true
    }

    func restarted() -> VolatileSettingsStore { VolatileSettingsStore(durable: durable) }

    private func set(_ value: Any?, for key: String) {
        events.append("write:\(key)")
        if let value { volatile[key] = value } else { volatile.removeValue(forKey: key) }
    }
}
