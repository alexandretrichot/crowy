import AppKit
import Carbon.HIToolbox

/// Registers a global hotkey via Carbon `RegisterEventHotKey`. Supports live
/// re-registration when the user changes the shortcut in Settings.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private static var onPress: (() -> Void)?

    /// Registers (or re-registers) the global hotkey. Safe to call repeatedly;
    /// previous registration is unwound first. Skips if the binding has no modifier.
    func register(binding: HotkeyBinding, onPress: @escaping () -> Void) {
        unregister()
        guard binding.hasModifier else { return }
        Self.onPress = onPress

        installEventHandlerIfNeeded()

        let signature: OSType = fourCharCode("PSTE")
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            self.hotKeyRef = ref
        } else {
            NSLog("HotkeyManager: RegisterEventHotKey failed status=\(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        // Keep the event handler installed across re-registrations; only the
        // hotkey ref needs swapping.
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                HotkeyManager.onPress?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func fourCharCode(_ s: String) -> OSType {
        var result: OSType = 0
        for char in s.utf8.prefix(4) {
            result = (result << 8) | OSType(char)
        }
        return result
    }
}
