import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Hotkey-recording control. Displays the current binding; on click, captures the
/// next keyDown that includes at least one modifier and writes it back.
struct HotkeyRecorderView: View {

    @Binding var binding: HotkeyBinding

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? "Press a shortcut…" : binding.displayString)
                .font(.system(.body, design: .default).monospacedDigit())
                .frame(minWidth: 110, alignment: .center)
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
        }
        .controlSize(.regular)
        .onDisappear { stopRecording() }
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleEvent(event)
        }
    }

    private func stopRecording() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
    }

    /// Returns `nil` if the event was consumed (recording flow), otherwise the event passes through.
    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        // Escape cancels.
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return nil
        }

        guard event.type == .keyDown else { return nil }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let usableMods = mods.intersection([.command, .option, .control, .shift])
        guard !usableMods.isEmpty else {
            // Bare key with no modifier — reject (would block normal typing globally).
            NSSound.beep()
            return nil
        }

        binding = HotkeyBinding(
            keyCode: UInt16(event.keyCode),
            modifierFlags: usableMods.rawValue
        )
        stopRecording()
        return nil
    }
}
