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

    /// Types the given text at the current cursor position using CGEvent keyboard simulation
    func typeText(_ text: String) throws {
        print("[Jetvoice] TextInjector.typeText called with \(text.count) characters")

        // Check Accessibility permission
        let isTrusted = AXIsProcessTrusted()
        print("[Jetvoice] AXIsProcessTrusted: \(isTrusted)")

        guard isTrusted else {
            print("[Jetvoice] ERROR: Accessibility not granted")
            throw InjectionError.accessibilityNotGranted
        }

        // Remember which app we're injecting into
        targetAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        print("[Jetvoice] Target app: \(targetAppBundleId ?? "unknown")")

        // Don't inject if Jetvoice itself is frontmost (user clicked menu bar icon)
        if targetAppBundleId?.contains("Jetvoice") == true {
            print("[Jetvoice] Jetvoice is frontmost - skipping injection")
            throw InjectionError.focusLost
        }

        print("[Jetvoice] Starting to type text...")
        // Type each character
        for (index, character) in text.enumerated() {
            // Check focus BEFORE typing to detect loss immediately and prevent system beeps
            let currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if currentApp != targetAppBundleId {
                print("[Jetvoice] Focus lost at character \(index)! Was: \(targetAppBundleId ?? "unknown"), Now: \(currentApp ?? "unknown")")
                throw InjectionError.focusLost
            }

            try typeCharacter(character)
            // Small delay to prevent dropped characters
            usleep(3000)  // 3ms
        }
        print("[Jetvoice] Finished typing \(text.count) characters")
    }

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

    private func typeCharacter(_ char: Character) throws {
        let string = String(char)

        // Handle newlines specially
        if char == "\n" {
            try pressKey(keyCode: 0x24)  // kVK_Return
            return
        }

        // Handle tabs
        if char == "\t" {
            try pressKey(keyCode: 0x30)  // kVK_Tab
            return
        }

        // For regular characters, use Unicode input
        for scalar in string.unicodeScalars {
            try typeUnicodeScalar(scalar)
        }
    }

    private func pressKey(keyCode: CGKeyCode) throws {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw InjectionError.eventCreationFailed
        }

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func typeUnicodeScalar(_ scalar: Unicode.Scalar) throws {
        // Create key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            throw InjectionError.eventCreationFailed
        }

        // Set the Unicode string
        var unicodeChar = UniChar(scalar.value)
        keyDownEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)

        // Create key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            throw InjectionError.eventCreationFailed
        }
        keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)

        // Post events
        keyDownEvent.post(tap: .cgAnnotatedSessionEventTap)
        keyUpEvent.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Alternative method: Copy text to clipboard and simulate Cmd+V paste
    /// This is more reliable for long text
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

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        try simulatePaste()

        // Restore previous clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
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
