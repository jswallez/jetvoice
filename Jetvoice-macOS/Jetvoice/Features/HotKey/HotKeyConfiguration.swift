//
//  HotKeyConfiguration.swift
//  Jetvoice
//
//  Configuration model for customizable keyboard shortcuts
//

import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Represents a keyboard shortcut configuration with key code and modifiers
struct HotKeyConfiguration: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64  // CGEventFlags raw value

    // MARK: - Default Configuration

    /// Default hotkey: Option+Space
    static let defaultHotKey = HotKeyConfiguration(
        keyCode: UInt16(kVK_Space),
        modifiers: CGEventFlags.maskAlternate.rawValue
    )

    // MARK: - UserDefaults Storage

    private static let storageKey = "customHotKey"

    /// Save configuration to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Load configuration from UserDefaults, or return default
    static func load() -> HotKeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
            return .defaultHotKey
        }
        return config
    }

    /// Reset to default configuration
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - CGEventFlags Conversion

    var cgModifiers: CGEventFlags {
        CGEventFlags(rawValue: modifiers)
    }

    // MARK: - Display String

    /// Human-readable display string (e.g., "⌥ Space", "⌘⇧ K")
    var displayString: String {
        var parts: [String] = []
        let flags = cgModifiers

        // Add modifier symbols in standard macOS order
        if flags.contains(.maskControl) {
            parts.append("⌃")
        }
        if flags.contains(.maskAlternate) {
            parts.append("⌥")
        }
        if flags.contains(.maskShift) {
            parts.append("⇧")
        }
        if flags.contains(.maskCommand) {
            parts.append("⌘")
        }

        // Add key name
        parts.append(keyName)

        return parts.joined(separator: "")
    }

    /// Human-readable key name
    var keyName: String {
        // Common key names
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Escape"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        default:
            // Try to get character from key code
            return characterForKeyCode(keyCode) ?? "Key \(keyCode)"
        }
    }

    /// Convert key code to character string using TIS (Text Input Source)
    private func characterForKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength: Int = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,  // No modifiers for base character
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &actualLength,
            &chars
        )

        guard status == noErr, actualLength > 0 else {
            return nil
        }

        return String(utf16CodeUnits: chars, count: actualLength).uppercased()
    }
}
