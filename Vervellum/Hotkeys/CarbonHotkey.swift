import AppKit
import Carbon.HIToolbox

/// A global hotkey registered via Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys need **no special permission** — unlike `CGEventTap` (Input
/// Monitoring) or `NSEvent.addGlobalMonitorForEvents` (Accessibility). Summoning
/// the panel is Vervellum's core interaction, so it must work the moment the app
/// is launched, with no trip to System Settings and no TCC prompt.
///
/// `RegisterEventHotKey` is a Carbon *Event Manager* call, which remains supported
/// in the 64-bit macOS SDK; only the Carbon **UI** toolbox was removed. Every
/// shortcut manager on the platform still uses it.
final class CarbonHotkey {

    /// Invoked on the main thread when the hotkey fires.
    var onPressed: (() -> Void)?

    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Four-char signature `'VRVL'`.
    private static let signature: OSType = 0x5652_564C

    init(identifier: UInt32) {
        self.identifier = identifier
    }

    deinit { unregister() }

    /// Registers the shortcut, replacing any previous one. Returns false when the
    /// combination is already claimed by another app or by the system — the caller
    /// surfaces that as "this shortcut is taken" rather than failing silently.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Returning `noErr` means "handled", and Carbon stops walking the handler
        // chain at the first one that says so. Every `CarbonHotkey` instance installs
        // its own handler on the *same* application event target, so a handler that
        // claimed every hot-key press would swallow the other instances' events — with
        // two shortcuts registered, whichever was installed last would be the only one
        // that ever fired. A press that is not ours must fall through with
        // `eventNotHandledErr`.
        let handlerCallback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()

            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            guard status == noErr,
                  pressedID.signature == CarbonHotkey.signature,
                  pressedID.id == me.identifier
            else { return OSStatus(eventNotHandledErr) }

            DispatchQueue.main.async { me.onPressed?() }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            // Roll back the installed handler so a failed registration doesn't
            // leave a dangling event handler behind.
            unregister()
            NSLog("Vervellum: failed to register Carbon hotkey \(identifier): status \(registerStatus)")
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
