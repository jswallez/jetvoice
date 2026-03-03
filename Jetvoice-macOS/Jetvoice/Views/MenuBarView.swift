//
//  MenuBarView.swift
//  Jetvoice
//
//  Main menu bar popover content
//  Updated for macOS 15+ using @Observable pattern
//

import SwiftUI

struct MenuBarView: View {
    // Use @Bindable for @Observable classes when you need bindings
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Status Header
            statusHeader

            Divider()

            // Recording Button
            recordingButton

            // Processing indicator
            if appState.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Transcribing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Pending Transcription (focus lost during injection)
            if let pending = appState.pendingTranscription {
                pendingTranscriptionView(pending)
            }

            // Last Transcription
            if let transcription = appState.lastTranscription, appState.pendingTranscription == nil {
                lastTranscriptionView(transcription)
            }

            // Error display
            if let error = appState.error {
                errorView(error)
            }

            Divider()

            // Footer Actions
            footerActions
        }
        .frame(width: 280)
        .padding(12)
        .onAppear {
            appState.refreshPermissions()
        }
    }

    // MARK: - Subviews

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.headline)
            Spacer()

            // Permission warning
            if !appState.permissionsGranted.allGranted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Some permissions are missing")
            }
        }
        .padding(.horizontal)
    }

    private var recordingButton: some View {
        Button {
            Task {
                await appState.toggleRecording()
            }
        } label: {
            HStack {
                Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                Text(appState.isRecording ? "Stop Recording (\(appState.hotKeyManager.currentConfiguration.displayString))" : "Start Recording (\(appState.hotKeyManager.currentConfiguration.displayString))")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.isRecording ? .orange : .accentColor)
        .disabled(appState.isProcessing || !appState.permissionsGranted.microphone)
        .padding(.horizontal)
    }

    private func pendingTranscriptionView(_ transcription: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Pending - Copied to clipboard")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                    Spacer()
                }

                Text(transcription)
                    .font(.body)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcription, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        appState.clearPendingTranscription()
                    } label: {
                        Label("Dismiss", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func lastTranscriptionView(_ transcription: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Last Transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcription, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
                }

                Text(transcription)
                    .font(.body)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    private func errorView(_ error: AppError) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
        .padding(.horizontal)
    }

    private var footerActions: some View {
        HStack {
            Button("Settings") {
                // Get the AppDelegate and show settings window
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.showSettings()
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if appState.isRecording { return .orange }
        if appState.isProcessing { return .purple }
        if !appState.permissionsGranted.allGranted { return .yellow }
        return .green
    }

    private var statusText: String {
        if appState.isRecording { return "Recording..." }
        if appState.isProcessing { return "Transcribing..." }
        if !appState.permissionsGranted.allGranted { return "Setup Required" }
        return "Ready"
    }
}

#Preview {
    MenuBarView(appState: AppState())
}
