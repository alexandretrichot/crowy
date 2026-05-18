import AppKit
import Carbon.HIToolbox

/// Persisted global hotkey: a key code plus modifier flags.
/// Stored in NSEvent format; converted to Carbon at registration time.
struct HotkeyBinding: Codable, Equatable {

    /// `NSEvent.keyCode` value — same numeric space as Carbon `kVK_*`.
    var keyCode: UInt16

    /// Raw `NSEvent.ModifierFlags.deviceIndependentFlagsMask` bits.
    var modifierFlags: UInt

    static let `default` = HotkeyBinding(
        keyCode: UInt16(kVK_ANSI_V),
        modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
    )

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        let mods = modifiers
        if mods.contains(.command) { mask |= UInt32(cmdKey) }
        if mods.contains(.option)  { mask |= UInt32(optionKey) }
        if mods.contains(.shift)   { mask |= UInt32(shiftKey) }
        if mods.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// User-facing string like "⌘⌥V".
    var displayString: String {
        displayKeys.joined()
    }

    /// One element per keycap. Command first (Crowy convention), then the rest
    /// in standard order. Special keys (e.g. "Space") stay grouped, so we can't
    /// just split `displayString` by character.
    var displayKeys: [String] {
        var keys: [String] = []
        let mods = modifiers
        if mods.contains(.command) { keys.append("⌘") }
        if mods.contains(.control) { keys.append("⌃") }
        if mods.contains(.option)  { keys.append("⌥") }
        if mods.contains(.shift)   { keys.append("⇧") }
        keys.append(Self.keyName(for: keyCode))
        return keys
    }

    /// True when at least one modifier is set — required for a usable global hotkey.
    var hasModifier: Bool {
        !modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }

    // MARK: - Key code → glyph

    private static func keyName(for keyCode: UInt16) -> String {
        if let special = specialKeyNames[Int(keyCode)] { return special }

        // Fall back to the layout-aware character produced by this key with no modifiers.
        if let chars = charactersForKeyCode(keyCode),
           let first = chars.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Space: "Space",
        kVK_Delete: "⌫",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_DownArrow: "↓",
        kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Reads the current keyboard layout to map keyCode → typed character.
    /// `UCKeyTranslate` returns whatever the user's layout produces (AZERTY/QWERTY/etc.).
    private static func charactersForKeyCode(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
