//
//  TextInjector.swift
//  Jetvoice
//
//  Types transcribed text at the current cursor position using CGEvent
//

import Foundation
import CoreGraphics
import AppKit

final class TextInjector {

    enum InjectionError: LocalizedError {
        case accessibilityNotGranted
        case eventCreationFailed
        case focusLost  // User switched to another app during injection

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permission is required to type text"
            case .eventCreationFailed:
                return "Failed to create keyboard event"
            case .focusLost:
                return "Target application lost focus during text injection"
            }
        }
    }

    // Track the frontmost app when injection starts
    private var targetAppBundleId: String?

    /// Remember the app that should receive injection (called when recording starts)
    func rememberTargetApp() {
        targetAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        print("[Jetvoice] Remembered target app: \(targetAppBundleId ?? "unknown")")
    }

    /// Check if we can safely inject (target app still has focus)
    func canInject() -> Bool {
        let currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // If we haven't remembered a target, just check it's not Jetvoice
        guard let target = targetAppBundleId else {
            return currentApp != nil && !currentApp!.contains("Jetvoice")
        }

        // Check if the original target app is still frontmost
        return currentApp == target
    }

    /// Copy text to clipboard and simulate Cmd+V paste, then restore the user's
    /// previous clipboard contents (all types, not just plain text).
    func pasteText(_ text: String) throws {
        guard AXIsProcessTrusted() else {
            throw InjectionError.accessibilityNotGranted
        }

        // Check focus before pasting
        let currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let target = targetAppBundleId, currentApp != target {
            print("[Jetvoice] Focus lost before paste! Was: \(target), Now: \(currentApp ?? "unknown")")
            throw InjectionError.focusLost
        }
        if currentApp?.contains("Jetvoice") == true {
            print("[Jetvoice] Jetvoice is frontmost - skipping paste")
            throw InjectionError.focusLost
        }

        // Snapshot the full current clipboard (every representation: RTF, images,
        // files, …) so we can restore exactly what the user had — not just text.
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            var copiedAnything = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    copiedAnything = true
                }
            }
            return copiedAnything ? copy : nil
        }

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        try simulatePaste()

        // Restore previous clipboard after a delay (500ms to handle slow apps like Electron)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let snapshot, !snapshot.isEmpty else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(snapshot)
        }
    }

    private func simulatePaste() throws {
        // Key code for 'V'
        let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            throw InjectionError.eventCreationFailed
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(10000)  // 10ms delay
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
