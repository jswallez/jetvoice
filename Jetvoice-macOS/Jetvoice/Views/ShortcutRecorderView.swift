//
//  ShortcutRecorderView.swift
//  Jetvoice
//
//  A SwiftUI view that captures keyboard shortcuts when clicked
//

import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let cancelShortcutRecording = Notification.Name("cancelShortcutRecording")
}

struct ShortcutRecorderView: View {
    @Binding var configuration: HotKeyConfiguration
    let onRecordingStarted: () -> Void
    let onRecordingEnded: () -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        Button {
            if isRecording {
                cancelRecording()
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press shortcut...")
                        .foregroundStyle(.secondary)
                } else {
                    Text(configuration.displayString)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isRecording ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            // Clean up monitor if view disappears while recording
            removeMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelShortcutRecording)) { _ in
            cancelRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }

        isRecording = true
        onRecordingStarted()

        // Install local event monitor for key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            // Check if Escape was pressed to cancel
            if event.keyCode == UInt16(kVK_Escape) {
                // Defer to avoid removing monitor while inside callback
                DispatchQueue.main.async {
                    self.cancelRecording()
                }
                return nil  // Consume the event
            }

            // Get modifiers (excluding caps lock and function keys)
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])

            // Require at least one modifier for non-function keys
            let functionKeyCodes: Set<UInt16> = [
                UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
                UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
                UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
                UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15)
            ]
            let isFunctionKey = functionKeyCodes.contains(event.keyCode)

            if modifiers.isEmpty && !isFunctionKey {
                // Don't accept shortcuts without modifiers (except F-keys)
                return nil
            }

            // Convert NSEvent modifiers to CGEventFlags
            var cgFlags: CGEventFlags = []
            if modifiers.contains(.control) {
                cgFlags.insert(.maskControl)
            }
            if modifiers.contains(.option) {
                cgFlags.insert(.maskAlternate)
            }
            if modifiers.contains(.shift) {
                cgFlags.insert(.maskShift)
            }
            if modifiers.contains(.command) {
                cgFlags.insert(.maskCommand)
            }

            // Capture the new configuration
            let newConfig = HotKeyConfiguration(
                keyCode: event.keyCode,
                modifiers: cgFlags.rawValue
            )

            // Defer to avoid removing monitor while inside callback
            DispatchQueue.main.async {
                self.finishRecording(with: newConfig)
            }

            return nil  // Consume the event
        }
    }

    private func finishRecording(with newConfig: HotKeyConfiguration) {
        guard isRecording else { return }

        removeMonitor()
        configuration = newConfig
        isRecording = false
        onRecordingEnded()
    }

    private func cancelRecording() {
        guard isRecording else { return }

        removeMonitor()
        isRecording = false
        onRecordingEnded()
    }

    private func removeMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var config = HotKeyConfiguration.defaultHotKey

        var body: some View {
            VStack {
                ShortcutRecorderView(
                    configuration: $config,
                    onRecordingStarted: {},
                    onRecordingEnded: {}
                )
                Text("Current: \(config.displayString)")
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
