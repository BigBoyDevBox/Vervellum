import AppKit

extension NSApplication {

    /// Empty on purpose. `.activateAllWindows` raises every window belonging to the app
    /// Vervellum is returning to, not only the workspace the user left in front.
    static let vervellumRestoreActivationOptions: NSApplication.ActivationOptions = []

    /// Cooperatively returns focus without rearranging the other application's windows.
    func restoreActivation(to application: NSRunningApplication) {
        yieldActivation(to: application)
        application.activate(options: Self.vervellumRestoreActivationOptions)
    }

    /// Reverts Vervellum to its menu-bar agent policy (`.accessory`, no Dock icon),
    /// **unless another ordinary window is still visible**.
    ///
    /// Vervellum is an `.accessory` app; it switches to `.regular` while a titled window
    /// (Settings) is open so that window can take focus, and each such window calls
    /// this when it closes. The guard — ignore the window that's closing
    /// (`excluding`) and stay `.regular` if any other titled, main-capable window
    /// remains — means closing one window while another is still open no longer drops
    /// the Dock presence the open one needs. The borderless research panel is
    /// explicitly not main-capable, so it is never counted.
    func revertToAccessoryIfNoOrdinaryWindows(excluding window: NSWindow?) {
        // `isVisible` is false for a miniaturized window, but a minimized Settings
        // window still needs the app to stay `.regular` — dropping to `.accessory`
        // removes its Dock thumbnail and strands it off-screen.
        let otherOrdinaryWindowOpen = windows.contains {
            $0 != window && ($0.isVisible || $0.isMiniaturized) && $0.canBecomeMain
        }
        if !otherOrdinaryWindowOpen { setActivationPolicy(.accessory) }
    }
}
