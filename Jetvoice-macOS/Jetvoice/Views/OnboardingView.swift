//
//  OnboardingView.swift
//  Jetvoice
//
//  First-launch permission setup flow
//  Updated for macOS 15+ using @Observable pattern
//

import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    microphoneStep
                case 2:
                    accessibilityStep
                case 3:
                    inputMonitoringStep
                case 4:
                    apiKeyStep
                default:
                    EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()
        }
        .frame(width: 450, height: 400)
        .onAppear {
            appState.refreshPermissions()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("Welcome to Jetvoice")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Transcribe your voice instantly with AI.\nPress Option+Space to start recording, press again to stop.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Get Started") {
                withAnimation {
                    currentStep = 1
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private var microphoneStep: some View {
        PermissionStepView(
            icon: appState.permissionsGranted.microphone ? "checkmark.circle.fill" : "mic.slash.fill",
            iconColor: appState.permissionsGranted.microphone ? .green : .orange,
            title: "Microphone Access",
            description: "Jetvoice needs access to your microphone to record audio for transcription.",
            isGranted: appState.permissionsGranted.microphone,
            primaryButtonTitle: appState.permissionsGranted.microphone ? "Continue" : "Grant Microphone Access",
            primaryAction: {
                if appState.permissionsGranted.microphone {
                    withAnimation {
                        currentStep = 2
                    }
                } else {
                    Task {
                        _ = await appState.permissionManager.requestMicrophonePermission()
                        appState.refreshPermissions()
                    }
                    appState.permissionManager.openMicrophoneSettings()
                }
            }
        )
    }

    private var accessibilityStep: some View {
        PermissionStepView(
            icon: appState.permissionsGranted.accessibility ? "checkmark.circle.fill" : "keyboard",
            iconColor: appState.permissionsGranted.accessibility ? .green : .orange,
            title: "Accessibility Access",
            description: "Jetvoice needs accessibility permission to type transcribed text at your cursor position.",
            isGranted: appState.permissionsGranted.accessibility,
            primaryButtonTitle: appState.permissionsGranted.accessibility ? "Continue" : "Open System Settings",
            primaryAction: {
                if appState.permissionsGranted.accessibility {
                    withAnimation {
                        currentStep = 3
                    }
                } else {
                    appState.permissionManager.openAccessibilitySettings()
                }
            },
            secondaryButtonTitle: appState.permissionsGranted.accessibility ? nil : "Check Again",
            secondaryAction: {
                appState.refreshPermissions()
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissions()
        }
    }

    private var inputMonitoringStep: some View {
        PermissionStepView(
            icon: appState.permissionsGranted.inputMonitoring ? "checkmark.circle.fill" : "command.square",
            iconColor: appState.permissionsGranted.inputMonitoring ? .green : .orange,
            title: "Input Monitoring",
            description: "Jetvoice needs input monitoring permission to detect the global hotkey (Option+Space) from any app.",
            isGranted: appState.permissionsGranted.inputMonitoring,
            primaryButtonTitle: appState.permissionsGranted.inputMonitoring ? "Continue" : "Open System Settings",
            primaryAction: {
                if appState.permissionsGranted.inputMonitoring {
                    withAnimation {
                        currentStep = 4
                    }
                } else {
                    appState.permissionManager.openInputMonitoringSettings()
                }
            },
            secondaryButtonTitle: appState.permissionsGranted.inputMonitoring ? nil : "Check Again",
            secondaryAction: {
                appState.refreshPermissions()
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissions()
        }
    }

    @State private var apiKey: String = ""
    @State private var isKeyVisible: Bool = false
    @State private var apiKeySaved: Bool = false

    private var hasValidAPIKey: Bool {
        apiKeySaved || KeychainHelper.getAPIKey() != nil
    }

    private var apiKeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: hasValidAPIKey ? "checkmark.circle.fill" : "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(hasValidAPIKey ? .green : .orange)

            Text("Gemini API Key")
                .font(.title)
                .fontWeight(.bold)

            Text("Jetvoice uses Google's Gemini AI for transcription.\nYou'll need an API key to get started.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if hasValidAPIKey {
                Text("API key configured!")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        if isKeyVisible {
                            TextField("Paste your API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Paste your API key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            isKeyVisible.toggle()
                        } label: {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(width: 300)

                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get an API key from Google AI Studio")
                        }
                        .font(.caption)
                    }
                }
            }

            VStack(spacing: 12) {
                Button(hasValidAPIKey ? "Finish Setup" : "Save & Continue") {
                    if hasValidAPIKey {
                        completeOnboarding()
                    } else if !apiKey.isEmpty {
                        if KeychainHelper.saveAPIKey(apiKey) {
                            apiKeySaved = true
                            withAnimation {
                                completeOnboarding()
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasValidAPIKey && apiKey.isEmpty)

                if !hasValidAPIKey {
                    Button("Skip for now") {
                        completeOnboarding()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .onAppear {
            // Check if key already exists
            if let existingKey = KeychainHelper.getAPIKey(), !existingKey.isEmpty {
                apiKeySaved = true
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        appState.setupHotKey()
        dismiss()
    }
}

// MARK: - Permission Step View

struct PermissionStepView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let primaryButtonTitle: String
    let primaryAction: () -> Void
    var secondaryButtonTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.title)
                .fontWeight(.bold)

            Text(description)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button(primaryButtonTitle) {
                    primaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let secondaryTitle = secondaryButtonTitle {
                    Button(secondaryTitle) {
                        secondaryAction?()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }
}

#Preview {
    OnboardingView(appState: AppState())
}
