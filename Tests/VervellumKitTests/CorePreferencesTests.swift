import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

/// The settings both platforms share, tested against an in-memory store so the suite
/// never touches a real user's preferences on either.
final class CorePreferencesTests: XCTestCase {

    private func preferences(_ initial: [String: Any] = [:]) -> CorePreferences {
        CorePreferences(store: MemorySettingsStore(initial))
    }

    func testDefaultsForAnEmptyStore() {
        let settings = preferences()
        XCTAssertTrue(settings.historyEnabled)
        XCTAssertTrue(settings.showProcessTrail)
        XCTAssertTrue(settings.submitOnReturn)
        XCTAssertEqual(settings.textScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(settings.providerSettings.searchEndpoint, ProviderSettings.defaultSearchEndpoint)
    }

    /// On by design: a false positive costs a re-typed word, a false negative sends a
    /// live credential to a third party.
    func testRedactionIsOnByDefault() {
        XCTAssertTrue(preferences().redactSecrets)
    }

    func testRoundTripsThroughTheStore() {
        let store = MemorySettingsStore()
        let settings = CorePreferences(store: store)
        settings.textScale = 1.25
        settings.submitOnReturn = false
        settings.redactSecrets = false
        settings.providerSettings = ProviderSettings(modelEndpoint: "https://api.example.com/v1",
                                                     modelName: "some-model",
                                                     searchEndpoint: "https://search.example.com/mcp")

        let reloaded = CorePreferences(store: store)
        XCTAssertEqual(reloaded.textScale, 1.25, accuracy: 0.001)
        XCTAssertFalse(reloaded.submitOnReturn)
        XCTAssertFalse(reloaded.redactSecrets)
        XCTAssertEqual(reloaded.providerSettings.modelName, "some-model")
    }

    /// Clamping on *read* is what makes a corrupted settings file survivable without a
    /// reset — the alternative is an app the user has to delete a file to recover.
    func testClampsCorruptedValuesOnRead() {
        XCTAssertEqual(preferences(["textScale": 99.0]).textScale, 1.4, accuracy: 0.001)
        XCTAssertEqual(preferences(["textScale": 0.0]).textScale, 0.85, accuracy: 0.001)
        XCTAssertEqual(preferences(["textScale": Double.nan]).textScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(preferences(["textScale": Double.infinity]).textScale, 1.0, accuracy: 0.001)
    }

    func testClampsOnWrite() {
        let settings = preferences()
        settings.textScale = -5
        XCTAssertEqual(settings.textScale, 0.85, accuracy: 0.001)
    }

    /// An emptied search endpoint reverts to the documented default rather than leaving
    /// the app with no search at all.
    func testAnEmptySearchEndpointRevertsToTheDefault() {
        let settings = preferences()
        settings.providerSettings = ProviderSettings(modelEndpoint: "https://api.example.com/v1",
                                                     modelName: "m",
                                                     searchEndpoint: "   ")
        XCTAssertEqual(settings.providerSettings.searchEndpoint, ProviderSettings.defaultSearchEndpoint)
    }

    func testChangesAreAnnounced() {
        let settings = preferences()
        var announcements = 0
        settings.onChange = { announcements += 1 }
        settings.textScale = 1.1
        settings.historyEnabled = false
        settings.providerSettings = ProviderSettings(modelEndpoint: "https://a.example.com/v1",
                                                     modelName: "m")
        XCTAssertEqual(announcements, 3)
    }

    /// The file store must survive a number that round-tripped as an integer, which is
    /// what happens to `1.0` in a hand-edited settings file — and what JSON gives back
    /// for `1`. Tested against the real file store, because the in-memory one does no
    /// coercion and the assertion would pass vacuously through the default instead.
    func testTheFileStoreReadsAnIntegerAsADouble() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VervellumSettingsTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("settings.json")
        try #"{"textScale": 1, "historyEnabled": false}"#.write(to: file, atomically: true, encoding: .utf8)

        let store = JSONFileSettingsStore(url: file)
        XCTAssertEqual(store.double(for: "textScale"), 1.0)
        XCTAssertEqual(CorePreferences(store: store).textScale, 1.0, accuracy: 0.001)
        XCTAssertFalse(CorePreferences(store: store).historyEnabled)
    }

    func testTheFileStorePersistsAcrossInstances() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VervellumSettingsTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("settings.json")
        CorePreferences(store: JSONFileSettingsStore(url: file)).textScale = 1.3
        XCTAssertEqual(CorePreferences(store: JSONFileSettingsStore(url: file)).textScale,
                       1.3, accuracy: 0.001)
    }

    /// A settings file that will not parse must not stop the app launching.
    func testAnUnreadableFileReadsAsEmpty() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VervellumSettingsTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("settings.json")
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(CorePreferences(store: JSONFileSettingsStore(url: file)).textScale,
                       1.0, accuracy: 0.001)
    }
}
