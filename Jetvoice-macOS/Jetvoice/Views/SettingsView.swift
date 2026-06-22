//
//  SettingsView.swift
//  Jetvoice
//
//  App preferences window
//  Updated for macOS 15+ using @Observable pattern
//

import SwiftUI
import Observation
import ServiceManagement
import Security

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            APISettingsView()
                .tabItem {
                    Label("API", systemImage: "key")
                }

            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
        .padding(.top, 8)
    }
}

// MARK: - API Settings

enum GeminiModel: String, CaseIterable {
    case gemini25Flash = "gemini-2.5-flash"
    case gemini3Flash = "gemini-3.5-flash"

    var displayName: String {
        switch self {
        case .gemini25Flash: return "Gemini 2.5 Flash"
        case .gemini3Flash: return "Gemini 3.5 Flash"
        }
    }
}

struct APISettingsView: View {
    @State private var apiKey: String = ""
    @State private var savedKey: String = ""
    @State private var isKeyVisible: Bool = false
    @State private var saveStatus: SaveStatus = .none
    @AppStorage("selectedGeminiModel") private var selectedModel: String = GeminiModel.gemini25Flash.rawValue

    enum SaveStatus {
        case none, saved, error
    }

    private var hasUnsavedChanges: Bool {
        apiKey != savedKey
    }

    var body: some View {
        VStack(spacing: 0) {
            GroupBox("Gemini API Key") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter your Google Gemini API key to enable voice transcription. A Google billing account is required, free tier keys won't work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        if isKeyVisible {
                            TextField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            isKeyVisible.toggle()
                        } label: {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        if hasUnsavedChanges {
                            Button("Save") {
                                if KeychainHelper.saveAPIKey(apiKey) {
                                    savedKey = apiKey
                                    saveStatus = .saved
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        saveStatus = .none
                                    }
                                } else {
                                    saveStatus = .error
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Save") {}
                                .buttonStyle(.bordered)
                                .disabled(true)
                        }

                        if saveStatus == .saved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else if saveStatus == .error {
                            Label("Error saving", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }

                        Spacer()

                        Link("Get API Key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                            .font(.caption)
                    }
                }
                .padding(4)
            }

            GroupBox("Model") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(GeminiModel.allCases, id: \.rawValue) { model in
                        HStack {
                            Button {
                                selectedModel = model.rawValue
                            } label: {
                                HStack {
                                    Image(systemName: selectedModel == model.rawValue ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedModel == model.rawValue ? Color.accentColor : Color.secondary)
                                    Text(model.displayName)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(4)
            }
            .padding(.top, 12)

            Spacer()
        }
        .padding()
        .onAppear {
            let storedKey = KeychainHelper.getAPIKey() ?? ""
            apiKey = storedKey
            savedKey = storedKey
        }
    }
}

// MARK: - Keychain Helper

nonisolated enum KeychainHelper {
    private static let service = "ai.jetvoice.api"
    private static let account = "gemini-api-key"

    static func saveAPIKey(_ key: String) -> Bool {
        let data = key.data(using: .utf8)!

        // Delete existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("playSounds") private var playSounds = true
    @AppStorage("soundVolume") private var soundVolume = 0.6
    private let soundPlayer = SoundPlayer()

    // Hotkey configuration
    @State private var hotKeyConfig = HotKeyConfiguration.load()
    @State private var isRecordingShortcut = false

    // 5 discrete volume levels: 0.2, 0.4, 0.6, 0.8, 1.0
    private let volumeSteps: [Double] = [0.2, 0.4, 0.6, 0.8, 1.0]

    private var volumeStepIndex: Int {
        // Find closest step
        let index = volumeSteps.enumerated().min(by: { abs($0.element - soundVolume) < abs($1.element - soundVolume) })?.offset ?? 2
        return index
    }

    var body: some View {
        VStack(spacing: 0) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                    Divider()
                    Toggle("Play sound feedback", isOn: $playSounds)
                    Text("Plays a sound when transcription completes or is canceled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)

                    if playSounds {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                            Slider(
                                value: $soundVolume,
                                in: 0.2...1.0,
                                step: 0.2
                            )
                            .onChange(of: soundVolume) { _, _ in
                                soundPlayer.playTranscribedSound()
                            }
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hotkey")
                        Spacer()
                        ShortcutRecorderView(
                            configuration: $hotKeyConfig,
                            onRecordingStarted: {
                                isRecordingShortcut = true
                                // Temporarily disable the global hotkey while recording
                                sharedAppState.hotKeyManager.stop()
                            },
                            onRecordingEnded: {
                                isRecordingShortcut = false
                                // Save and re-enable hotkey with new configuration
                                sharedAppState.hotKeyManager.updateHotKey(hotKeyConfig)
                            }
                        )
                    }

                    HStack {
                        Spacer()
                        if isRecordingShortcut {
                            Button("Cancel") {
                                // Post notification to cancel recording
                                NotificationCenter.default.post(name: .cancelShortcutRecording, object: nil)
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        } else if hotKeyConfig != HotKeyConfiguration.defaultHotKey {
                            Button("Reset to Default") {
                                hotKeyConfig = HotKeyConfiguration.defaultHotKey
                                sharedAppState.hotKeyManager.updateHotKey(hotKeyConfig)
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }
                    }
                }
                .padding(4)
            }
            .padding(.top, 12)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Permissions Settings

struct PermissionsSettingsView: View {
    @State private var permissionManager = PermissionManager()
    private var hotKeyDescription: String {
        "Detect \(HotKeyConfiguration.load().displayString) hotkey globally"
    }

    var body: some View {
        VStack(spacing: 0) {
            GroupBox("Required Permissions") {
                VStack(spacing: 0) {
                    PermissionRow(
                        title: "Microphone",
                        description: "Record voice for transcription",
                        isGranted: permissionManager.state.microphone,
                        action: {
                            Task {
                                _ = await permissionManager.requestMicrophonePermission()
                                permissionManager.refreshAllPermissions()
                            }
                            permissionManager.openMicrophoneSettings()
                        }
                    )

                    Divider().padding(.vertical, 8)

                    PermissionRow(
                        title: "Accessibility",
                        description: "Type text at cursor position",
                        isGranted: permissionManager.state.accessibility,
                        action: {
                            if !permissionManager.state.accessibility {
                                permissionManager.requestAccessibilityPermission()
                            }
                            permissionManager.openAccessibilitySettings()
                        }
                    )

                    Divider().padding(.vertical, 8)

                    PermissionRow(
                        title: "Input Monitoring",
                        description: hotKeyDescription,
                        isGranted: permissionManager.state.inputMonitoring,
                        action: {
                            if !permissionManager.state.inputMonitoring {
                                _ = permissionManager.requestInputMonitoringPermission()
                            }
                            permissionManager.openInputMonitoringSettings()
                        }
                    )
                }
                .padding(4)
            }

            Button("Refresh Status") {
                permissionManager.refreshAllPermissions()
            }
            .padding(.top, 16)

            Spacer()
        }
        .padding()
        .onAppear {
            permissionManager.refreshAllPermissions()
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Jetvoice")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.appVersion)")
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                Text("Precise, fast and easy voice transcription for Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 2) {
                    Text("Created by")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("@jswallez", destination: URL(string: "https://x.com/jswallez")!)
                        .font(.caption)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Link("Terms", destination: URL(string: "https://jswallez.com/jetvoice/terms")!)
                Link("Privacy", destination: URL(string: "https://jswallez.com/jetvoice/privacy")!)
            }
            .font(.caption)
        }
        .padding()
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

#Preview {
    SettingsView()
}
