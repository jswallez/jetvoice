//
//  PermissionManager.swift
//  Jetvoice
//
//  Handles all permission checks and requests
//  Updated for macOS 15+ using @Observable macro
//

import Foundation
import AVFoundation
import CoreGraphics
import AppKit
import Observation

@MainActor
@Observable
final class PermissionManager {
    var state = PermissionState()

    init() {
        refreshAllPermissions()
    }

    func refreshAllPermissions() {
        state.microphone = checkMicrophonePermission()
        state.accessibility = checkAccessibilityPermission()
        state.inputMonitoring = checkInputMonitoringPermission()
    }

    // MARK: - Microphone

    func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility (for posting keyboard events)

    func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Input Monitoring (for global hotkey)

    func checkInputMonitoringPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
