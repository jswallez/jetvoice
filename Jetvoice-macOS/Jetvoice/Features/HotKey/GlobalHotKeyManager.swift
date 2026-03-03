//
//  GlobalHotKeyManager.swift
//  Jetvoice
//
//  CGEventTap-based global hotkey capture (configurable shortcut)
//  Updated for macOS 15+ using @Observable macro
//

import Foundation
import CoreGraphics
import Carbon.HIToolbox
import Observation

@Observable
final class GlobalHotKeyManager {
    var isEnabled = false

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onHotKeyPressed: (() -> Void)?
    private var retainedSelf: UnsafeMutableRawPointer?  // Prevent use-after-free in CGEventTap callback

    // Configurable hotkey (loaded from UserDefaults, defaults to Option+Space)
    fileprivate var hotKeyCode: CGKeyCode
    fileprivate var requiredModifiers: CGEventFlags
    fileprivate var isModifierOnlyHotKey: Bool

    init() {
        let config = HotKeyConfiguration.load()
        self.hotKeyCode = CGKeyCode(config.keyCode)
        self.requiredModifiers = config.cgModifiers
        self.isModifierOnlyHotKey = config.isModifierOnly
    }

    deinit {
        stop()
    }

    /// Update the hotkey configuration and restart listening
    func updateHotKey(_ config: HotKeyConfiguration) {
        hotKeyCode = CGKeyCode(config.keyCode)
        requiredModifiers = config.cgModifiers
        isModifierOnlyHotKey = config.isModifierOnly
        config.save()

        // Restart listening with new configuration
        if let callback = onHotKeyPressed {
            stop()
            _ = start(onHotKeyPressed: callback)
        }
    }

    /// Get the current hotkey configuration
    var currentConfiguration: HotKeyConfiguration {
        HotKeyConfiguration(keyCode: UInt16(hotKeyCode), modifiers: requiredModifiers.rawValue, isModifierOnly: isModifierOnlyHotKey)
    }

    /// Start listening for the configured hotkey
    /// - Parameter onHotKeyPressed: Callback when hotkey is pressed
    /// - Returns: true if started successfully, false if permission denied
    func start(onHotKeyPressed: @escaping () -> Void) -> Bool {
        self.onHotKeyPressed = onHotKeyPressed

        // Check for Input Monitoring permission
        guard CGPreflightListenEventAccess() else {
            // Request permission - this shows system dialog
            CGRequestListenEventAccess()
            return false
        }

        // Create event tap for both keyDown and keyUp events
        // We need to capture both to fully suppress the key from reaching system dictation
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // Use Unmanaged.passRetained to prevent use-after-free if callback fires during dealloc
        let userInfo = Unmanaged.passRetained(self).toOpaque()
        retainedSelf = userInfo

        // Use cghidEventTap to intercept at HID level (before system shortcuts)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: globalHotKeyCallback,
            userInfo: userInfo
        ) else {
            print("Failed to create HID event tap, falling back to session tap")
            // Fallback to session tap if HID tap fails
            guard let sessionTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: globalHotKeyCallback,
                userInfo: userInfo
            ) else {
                print("Failed to create event tap")
                return false
            }
            eventTap = sessionTap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, sessionTap, 0)

            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: sessionTap, enable: true)
                DispatchQueue.main.async {
                    self.isEnabled = true
                }
                return true
            }
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            DispatchQueue.main.async {
                self.isEnabled = true
            }
            return true
        }

        return false
    }

    /// Stop listening for hotkeys
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        // Release the retained self reference from passRetained
        if let ptr = retainedSelf {
            Unmanaged<GlobalHotKeyManager>.fromOpaque(ptr).release()
            retainedSelf = nil
        }
        DispatchQueue.main.async {
            self.isEnabled = false
        }
    }

    /// Called from the C callback when a key event is detected
    /// - Parameters:
    ///   - keyCode: The key code of the pressed key
    ///   - flags: The modifier flags
    ///   - isKeyDown: true for keyDown, false for keyUp
    /// - Returns: true if the event should be consumed
    // Track if we're waiting for key up (to prevent key repeat triggering multiple times)
    fileprivate var isKeyDown = false
    // Track modifier-only tap state (press + release without other keys)
    fileprivate var modifierTapPending = false

    fileprivate func handleKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, isKeyDown eventIsKeyDown: Bool) -> Bool {
        // Cancel modifier-only tap if any regular key is pressed
        if eventIsKeyDown {
            modifierTapPending = false
        }

        // Modifier-only hotkeys are handled in handleFlagsChanged
        guard !isModifierOnlyHotKey else { return false }

        // Check if this is our hotkey with required modifier
        let hasRequiredModifier = flags.contains(requiredModifiers)

        if keyCode == hotKeyCode && hasRequiredModifier {
            if eventIsKeyDown {
                // Only trigger on first keyDown, ignore auto-repeat
                if !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onHotKeyPressed?()
                    }
                }
            } else {
                // Key up - reset state
                isKeyDown = false
            }
            return true  // Consume the event
        }
        return false
    }

    /// Handle modifier key changes for modifier-only hotkeys (e.g., "Right ⌥" alone)
    fileprivate func handleFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard isModifierOnlyHotKey else { return false }
        guard keyCode == hotKeyCode else {
            // Different modifier key pressed - cancel pending tap
            modifierTapPending = false
            return false
        }

        guard let targetFlag = HotKeyConfiguration.modifierFlag(forKeyCode: UInt16(keyCode)) else {
            return false
        }

        if flags.contains(targetFlag) {
            // Modifier key went down
            modifierTapPending = true
        } else if modifierTapPending {
            // Modifier key went up after being pressed alone - trigger hotkey
            modifierTapPending = false
            DispatchQueue.main.async { [weak self] in
                self?.onHotKeyPressed?()
            }
        }

        return false  // Don't consume flagsChanged events
    }
}

// C callback function for CGEventTap
private func globalHotKeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle tap disabled event (system can disable taps if they're slow)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable the tap
        if let userInfo = userInfo {
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    // Handle modifier key changes (for modifier-only hotkeys)
    if type == .flagsChanged {
        if manager.handleFlagsChanged(keyCode: keyCode, flags: flags) {
            return nil
        }
        return Unmanaged.passRetained(event)
    }

    let isKeyDown = (type == .keyDown)

    if manager.handleKeyEvent(keyCode: keyCode, flags: flags, isKeyDown: isKeyDown) {
        return nil  // Consume the event (don't pass it to other apps or system)
    }

    return Unmanaged.passRetained(event)
}
