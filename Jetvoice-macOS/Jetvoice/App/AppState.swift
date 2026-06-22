//
//  AppState.swift
//  Jetvoice
//
//  Central state management for the app
//  Updated for macOS 15+ using @Observable macro
//

import SwiftUI
import Observation

// MARK: - App State (using modern @Observable macro)

@MainActor
@Observable
final class AppState {
    // MARK: - State
    var isRecording = false
    var isProcessing = false
    var recordingStartedAt: Date?   // drives the live elapsed timer while recording
    var processingStartedAt: Date?  // drives the live elapsed timer while transcribing
    var lastTranscription: String?
    var pendingTranscription: String?  // Transcription that couldn't be injected (user switched apps)
    var error: AppError?
    var permissionsGranted = PermissionState()

    // MARK: - Managers
    let audioRecorder: AudioRecorder
    let geminiService: GeminiService
    let textInjector: TextInjector
    let hotKeyManager: GlobalHotKeyManager
    let permissionManager: PermissionManager

    // Sound player for feedback sounds
    private let soundPlayer = SoundPlayer()

    init() {
        self.audioRecorder = AudioRecorder()
        self.geminiService = GeminiService()
        self.textInjector = TextInjector()
        self.hotKeyManager = GlobalHotKeyManager()
        self.permissionManager = PermissionManager()

        refreshPermissions()

        // Only setup hotkey if onboarding is complete (to avoid triggering permission prompts)
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            setupHotKey()
        }
    }

    // MARK: - Setup

    func setupHotKey() {
        let started = hotKeyManager.start { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.toggleRecording()
            }
        }

        if !started {
            print("Failed to start hotkey manager - Input Monitoring permission may be required")
        }
    }

    func refreshPermissions() {
        permissionManager.refreshAllPermissions()
        permissionsGranted = permissionManager.state
    }

    // MARK: - Recording Control

    private var isToggling = false  // Prevent multiple simultaneous toggles
    private var transcriptionTask: Task<Void, Never>?  // Track ongoing transcription for cancellation
    private var wasCanceled = false  // Track if user canceled to suppress errors
    private var wasAutoStopped = false  // Track if recording was auto-stopped due to max duration

    func toggleRecording() async {
        // If processing, cancel the transcription
        if isProcessing {
            print("[Jetvoice] Canceling transcription...")
            cancelTranscription()
            return
        }

        // Prevent re-entrancy - don't start if already toggling
        guard !isToggling else {
            print("[Jetvoice] Already toggling, ignoring")
            return
        }

        isToggling = true
        defer { isToggling = false }

        if isRecording {
            // Store the task so it can be cancelled
            transcriptionTask = Task {
                await stopRecordingAndTranscribe()
            }
            // Wait for completion (or cancellation)
            await transcriptionTask?.value
            transcriptionTask = nil
        } else {
            await startRecording()
        }
    }

    /// Cancel ongoing transcription
    private func cancelTranscription() {
        wasCanceled = true  // Flag to suppress any errors from in-flight API call
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isProcessing = false
        processingStartedAt = nil
        // Clear any error state - user intentionally canceled
        error = nil
        playCancelSound()
        print("[Jetvoice] Transcription canceled")
    }

    private func startRecording() async {
        guard permissionsGranted.microphone else {
            error = .microphonePermissionDenied
            return
        }

        // Clear previous error
        error = nil

        // Remember which app should receive the transcription
        textInjector.rememberTargetApp()

        do {
            try await audioRecorder.startRecording { [weak self] in
                // Called when max duration is reached (10 minutes)
                guard let self else { return }
                Task { @MainActor in
                    print("[Jetvoice] Max recording duration reached, auto-stopping")
                    self.wasAutoStopped = true
                    self.playStopSound()  // Play stop sound to notify user
                    await self.toggleRecording()
                }
            }
            isRecording = true
            recordingStartedAt = Date()
            wasAutoStopped = false  // Reset flag when starting new recording
        } catch {
            self.error = .recordingFailed(error.localizedDescription)
        }
    }

    private func stopRecordingAndTranscribe() async {
        isRecording = false
        recordingStartedAt = nil
        isProcessing = true
        processingStartedAt = Date()
        wasCanceled = false  // Reset cancel flag at start of transcription

        do {
            print("[Jetvoice] Stopping recording...")
            let audioData = try await audioRecorder.stopRecording()
            print("[Jetvoice] Audio data size: \(audioData.count) bytes")

            // Check if recording has actual audio content (not just WAV header)
            // A valid recording should be at least 10KB for ~0.3 seconds of audio
            guard audioData.count > 10_000 else {
                print("[Jetvoice] Recording too short, no audio content")
                throw AppError.noAudioRecorded
            }

            // Check for cancellation before API call
            try Task.checkCancellation()

            print("[Jetvoice] Sending to Gemini API...")
            let transcription = try await geminiService.transcribe(audioData: audioData)

            // Check for cancellation after API call
            try Task.checkCancellation()
            guard !wasCanceled else { return }

            print("[Jetvoice] Transcription received: \(transcription)")
            lastTranscription = transcription

            // Type the transcription at cursor
            guard permissionsGranted.accessibility else {
                print("[Jetvoice] ERROR: Accessibility not granted")
                error = .accessibilityPermissionDenied
                isProcessing = false
                processingStartedAt = nil
                return
            }

            // Check if we can still inject (user might have switched apps during API call)
            guard textInjector.canInject() else {
                print("[Jetvoice] Cannot inject - focus changed during transcription")
                handleFocusLost(transcription: transcription)
                playTranscribedSound()  // Still play sound - transcription is ready
                isProcessing = false
                processingStartedAt = nil
                return
            }

            print("[Jetvoice] Pasting transcription...")
            try textInjector.pasteText(transcription)
            print("[Jetvoice] Done pasting!")

            // Play transcribed sound on success
            playTranscribedSound()

            // Clear any pending transcription on success
            pendingTranscription = nil
        } catch is CancellationError {
            // Transcription was canceled by user - don't show error
            print("[Jetvoice] Transcription was canceled")
            // Cancel sound already played in cancelTranscription()
        } catch let injectionError as TextInjector.InjectionError where injectionError == .focusLost {
            // User switched apps - silently save to pending and clipboard
            print("[Jetvoice] Focus lost during injection - saving to pending")
            if let transcription = lastTranscription {
                handleFocusLost(transcription: transcription)
                playTranscribedSound()  // Still play sound - transcription is ready
            }
        } catch let error as AppError {
            // Don't show error if user canceled
            guard !wasCanceled else { return }
            print("[Jetvoice] AppError: \(error.localizedDescription)")
            self.error = error
        } catch {
            // Don't show error if user canceled
            guard !wasCanceled else { return }
            print("[Jetvoice] Error: \(error.localizedDescription)")
            self.error = .transcriptionFailed(error.localizedDescription)
        }

        isProcessing = false
        processingStartedAt = nil
    }

    /// Handle when user switches apps during text injection
    private func handleFocusLost(transcription: String) {
        // Save to pending (will show red dot indicator)
        pendingTranscription = transcription

        // Also copy to clipboard so user can paste manually
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcription, forType: .string)

        // Don't set error - this is handled gracefully
        // Don't play error sound - just silently save
        print("[Jetvoice] Transcription saved to clipboard and pending")
    }

    /// Clear pending transcription (after user has copied it)
    func clearPendingTranscription() {
        pendingTranscription = nil
    }

    // MARK: - Feedback

    // Sounds are on by default; only "playSounds == false" silences them.
    // Read UserDefaults directly since @AppStorage conflicts with @Observable.
    private var shouldPlaySounds: Bool {
        UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true
    }

    private func playTranscribedSound() {
        guard shouldPlaySounds else { return }
        soundPlayer.playTranscribedSound()
    }

    private func playCancelSound() {
        guard shouldPlaySounds else { return }
        soundPlayer.playCancelSound()
    }

    private func playStopSound() {
        guard shouldPlaySounds else { return }
        soundPlayer.playStopSound()
    }
}

// MARK: - Permission State

struct PermissionState: Equatable {
    var microphone: Bool = false
    var accessibility: Bool = false
    var inputMonitoring: Bool = false

    var allGranted: Bool {
        microphone && accessibility && inputMonitoring
    }
}

// MARK: - App Errors

enum AppError: LocalizedError, Identifiable, Equatable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case recordingFailed(String)
    case transcriptionFailed(String)
    case noAudioRecorded

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to record audio."
        case .accessibilityPermissionDenied:
            return "Accessibility access is required to type transcribed text."
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .noAudioRecorded:
            return "No audio was recorded."
        }
    }
}
