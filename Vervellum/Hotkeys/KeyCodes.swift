import Carbon.HIToolbox

/// Virtual key codes used by Vervellum's global shortcuts and panel key handling
/// (US layout, position-based — the *label* shown to the user is captured from the
/// event at record time, so a non-US layout still displays the right key).
enum KeyCode {
    static let escape: UInt32 = UInt32(kVK_Escape)          // 53
    static let space: UInt32 = UInt32(kVK_Space)            // 49
    static let `return`: UInt32 = UInt32(kVK_Return)        // 36
    static let keypadEnter: UInt32 = UInt32(kVK_ANSI_KeypadEnter) // 76
    static let upArrow: UInt32 = UInt32(kVK_UpArrow)        // 126
    static let downArrow: UInt32 = UInt32(kVK_DownArrow)    // 125
    static let leftArrow: UInt32 = UInt32(kVK_LeftArrow)    // 123
    static let rightArrow: UInt32 = UInt32(kVK_RightArrow)  // 124
    static let tab: UInt32 = UInt32(kVK_Tab)                // 48
    static let j: UInt32 = UInt32(kVK_ANSI_J)               // 38

    /// Carbon modifier-flag bits for `RegisterEventHotKey`.
    enum Modifier {
        static let command = UInt32(cmdKey)
        static let option = UInt32(optionKey)
        static let control = UInt32(controlKey)
        static let shift = UInt32(shiftKey)
    }
}
