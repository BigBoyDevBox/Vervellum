import AppKit

/// Program entry point.
///
/// Vervellum is a menu-bar agent (`LSUIElement`), so it runs as an `.accessory` app
/// with no Dock icon of its own. A plain `NSApplication` lifecycle (rather than the
/// SwiftUI `App` scene) keeps full control over the borderless research panel — a
/// SwiftUI `Scene` cannot express a non-activating panel that joins every Space.
@main
enum VervellumMain {

    /// Held for the life of the process. `NSApplication.delegate` is a **weak**
    /// reference, so a local would be free for ARC to release the moment it stopped
    /// being used — which is the line after it is assigned.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
