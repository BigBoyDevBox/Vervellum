import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class JSONFileSettingsStoreTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("settings.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSingleKeyWritePreservesExternalChanges() throws {
        let running = JSONFileSettingsStore(url: file)
        running.setString("old", for: "modelName")
        let external = JSONFileSettingsStore(url: file)
        external.setString("new", for: "modelName")
        external.setString("https://local.example/v1", for: "modelEndpoint")

        running.setBool(true, for: "shortcutInstalled")

        let saved = JSONFileSettingsStore(url: file)
        XCTAssertEqual(saved.string(for: "modelName"), "new")
        XCTAssertEqual(saved.string(for: "modelEndpoint"), "https://local.example/v1")
        XCTAssertEqual(saved.bool(for: "shortcutInstalled"), true)
        XCTAssertEqual(running.string(for: "modelName"), "new")
    }

    func testMalformedExternalEditsAreNotOverwritten() throws {
        let running = JSONFileSettingsStore(url: file)
        running.setString("old", for: "modelName")
        for edited in ["{ unfinished", "[]"] {
            try Data(edited.utf8).write(to: file)
            running.setBool(true, for: "shortcutInstalled")
            XCTAssertEqual(try Data(contentsOf: file), Data(edited.utf8))
        }
    }

    func testDeletingTheFileDoesNotResurrectCachedKeys() throws {
        let running = JSONFileSettingsStore(url: file)
        running.setString("old", for: "modelName")
        try FileManager.default.removeItem(at: file)
        running.setBool(true, for: "shortcutInstalled")
        XCTAssertNil(JSONFileSettingsStore(url: file).string(for: "modelName"))
    }

    func testKeyRemovalDoesNotRestoreExternallyRemovedKeys() {
        let running = JSONFileSettingsStore(url: file)
        running.setString("old", for: "removedExternally")
        running.setString("old", for: "removedLocally")
        let external = JSONFileSettingsStore(url: file)
        external.setString(nil, for: "removedExternally")

        running.setString(nil, for: "removedLocally")

        let saved = JSONFileSettingsStore(url: file)
        XCTAssertNil(saved.string(for: "removedExternally"))
        XCTAssertNil(saved.string(for: "removedLocally"))
    }
}
