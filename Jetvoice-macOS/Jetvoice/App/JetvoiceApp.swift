//
//  JetvoiceApp.swift
//  Jetvoice
//
//  Pure AppKit menu bar app - NO SwiftUI scenes to avoid duplicate icon bug
//  See: https://khorbushko.github.io/article/2021/04/30/minimal-macOS-menu-bar-extra's-app-with-SwiftUI.html
//

import SwiftUI
import AppKit

// Shared app state - single instance for the entire app
@MainActor
let sharedAppState = AppState()

// MARK: - Pure AppKit Entry Point (no SwiftUI App struct)

@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // Set as accessory app (menu bar only, no dock icon)
        app.setActivationPolicy(.accessory)

        app.run()
    }
}

// MARK: - App Delegate with NSStatusItem

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var iconUpdateTimer: Timer?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup Edit menu for Cmd+V support in text fields
        setupMainMenu()

        // Setup the status bar item
        setupStatusItem()

        // Use a simple timer to poll the state for icon updates
        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateStatusItemIcon()
            }
        }

        // Show onboarding on first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Jetvoice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (for Cmd+C, Cmd+V, Cmd+X, Cmd+A)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use custom Jetvoice icon from assets (template for menu bar)
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover will be created fresh each time it opens
        popover = nil
    }

    private var lastIconState: String = ""
    private var statusDotView: NSView?

    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }

        // Determine current state (pending/error takes priority when not recording/processing)
        let currentState: String
        if sharedAppState.isRecording {
            currentState = "recording"
        } else if sharedAppState.isProcessing {
            currentState = "processing"
        } else if sharedAppState.pendingTranscription != nil {
            currentState = "pending"
        } else if sharedAppState.error != nil {
            currentState = "error"
        } else {
            currentState = "ready"
        }

        // Only update if state changed
        guard currentState != lastIconState else { return }
        lastIconState = currentState

        // Always use the base template icon (white mic that adapts to menu bar)
        guard let image = NSImage(named: "MenuBarIcon") else { return }
        image.isTemplate = true
        button.image = image

        // Remove existing dot view if any
        statusDotView?.removeFromSuperview()
        statusDotView = nil

        // Add colored dot overlay for recording/processing/pending/error states
        if sharedAppState.isRecording {
            addStatusDot(to: button, color: NSColor(red: 1.0, green: 0.42, blue: 0.0, alpha: 1.0)) // Orange
        } else if sharedAppState.isProcessing {
            addStatusDot(to: button, color: NSColor(red: 0.6, green: 0.2, blue: 0.9, alpha: 1.0)) // Purple
        } else if sharedAppState.pendingTranscription != nil || sharedAppState.error != nil {
            addStatusDot(to: button, color: NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)) // Red
        }
    }

    private func addStatusDot(to button: NSStatusBarButton, color: NSColor) {
        let dotSize: CGFloat = 6
        let dotView = NSView(frame: NSRect(x: button.bounds.width - dotSize - 1,
                                            y: button.bounds.height - dotSize - 1,
                                            width: dotSize,
                                            height: dotSize))
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = color.cgColor
        dotView.layer?.cornerRadius = dotSize / 2

        button.addSubview(dotView)
        statusDotView = dotView
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        // Check if popover exists and is shown
        if let existingPopover = popover, existingPopover.isShown {
            existingPopover.performClose(nil)
            popover = nil
            return
        }

        // Close any existing popover first
        popover?.performClose(nil)
        popover = nil

        // Refresh permissions when opening
        sharedAppState.refreshPermissions()

        // Create a fresh popover
        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.animates = false

        let hostingController = NSHostingController(rootView: MenuBarView(appState: sharedAppState))
        let fittingSize = hostingController.sizeThatFits(in: CGSize(width: 300, height: 600))
        newPopover.contentSize = fittingSize
        newPopover.contentViewController = hostingController

        popover = newPopover
        // Offset the positioning rect to create natural gap below menu bar icon
        var positioningRect = button.bounds
        positioningRect.origin.y += 8
        newPopover.show(relativeTo: positioningRect, of: button, preferredEdge: .minY)

        // Make sure popover window can become key
        newPopover.contentViewController?.view.window?.makeKey()

        // Clear the red dot when user opens popover (they've seen the pending notification or error)
        // Move pending to lastTranscription so they can still see/copy it
        if let pending = sharedAppState.pendingTranscription {
            sharedAppState.lastTranscription = pending
            sharedAppState.clearPendingTranscription()
        }

        // Clear error after user has seen it (they opened the popover)
        // Keep error visible in the popover but clear the red dot on next state change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sharedAppState.error = nil
        }
    }

    // MARK: - Window Management

    func showSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Jetvoice Settings"
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.setContentSize(NSSize(width: 450, height: 300))
            settingsWindow?.center()
            // Prevent window from closing when app loses focus
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.hidesOnDeactivate = false
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let onboardingView = OnboardingView(appState: sharedAppState)
            let hostingController = NSHostingController(rootView: onboardingView)

            onboardingWindow = NSWindow(contentViewController: hostingController)
            onboardingWindow?.title = "Welcome to Jetvoice"
            onboardingWindow?.styleMask = [.titled, .closable]
            onboardingWindow?.setContentSize(NSSize(width: 450, height: 400))
            onboardingWindow?.center()
            // Prevent window from closing when app loses focus (e.g., opening System Settings)
            onboardingWindow?.isReleasedWhenClosed = false
            onboardingWindow?.hidesOnDeactivate = false
        }

        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up
        iconUpdateTimer?.invalidate()

        Task {
            await sharedAppState.audioRecorder.cancelRecording()
            sharedAppState.hotKeyManager.stop()
        }
    }

    // IMPORTANT: Keep app running when windows close (menu bar app behavior)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
