//
//  AudioRecorder.swift
//  Jetvoice
//
//  AVAudioEngine-based audio recording with format conversion for Gemini API
//  Updated for macOS 15+ with proper cleanup
//

import AVFoundation
import Foundation

actor AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var maxDurationTimer: Task<Void, Never>?

    private let bufferSize: AVAudioFrameCount = 4096

    // Target format for Gemini API (16kHz mono for efficiency)
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    // Maximum recording duration (10 minutes) to stay within Gemini API limits
    // At 16kHz mono 16-bit, 10 minutes produces ~19MB which is under the ~25MB inline limit
    static let maxRecordingDuration: TimeInterval = 10 * 60  // 10 minutes

    // Callback when max duration is reached
    private var onMaxDurationReached: (() -> Void)?

    /// Cancels any active recording and cleans up resources
    func cancelRecording() {
        maxDurationTimer?.cancel()
        maxDurationTimer = nil
        recordingStartTime = nil
        onMaxDurationReached = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        audioFile = nil

        // Clean up temp file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }

    enum RecorderError: LocalizedError {
        case engineNotAvailable
        case recordingInProgress
        case noRecordingAvailable
        case formatConversionFailed
        case inputNodeUnavailable

        var errorDescription: String? {
            switch self {
            case .engineNotAvailable:
                return "Audio engine is not available"
            case .recordingInProgress:
                return "A recording is already in progress"
            case .noRecordingAvailable:
                return "No recording available"
            case .formatConversionFailed:
                return "Failed to convert audio format"
            case .inputNodeUnavailable:
                return "Microphone input is not available"
            }
        }
    }

    func startRecording(onMaxDurationReached: @escaping () -> Void) throws {
        print("[Jetvoice] AudioRecorder.startRecording called")

        guard audioEngine == nil else {
            print("[Jetvoice] ERROR: Recording already in progress")
            throw RecorderError.recordingInProgress
        }

        self.onMaxDurationReached = onMaxDurationReached

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[Jetvoice] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Verify we have a valid input format
        guard inputFormat.sampleRate > 0 else {
            throw RecorderError.inputNodeUnavailable
        }

        // Create temporary file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "jetvoice_recording_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordingURL = fileURL

        // Create output format (PCM 16-bit for WAV)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            throw RecorderError.formatConversionFailed
        }

        // Create audio file
        audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        // Create converter for sample rate conversion
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.formatConversionFailed
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            Task {
                await self.processBuffer(buffer, converter: converter, outputFormat: outputFormat)
            }
        }

        engine.prepare()
        try engine.start()
        print("[Jetvoice] Audio engine started successfully")

        audioEngine = engine
        recordingStartTime = Date()

        // Start max duration timer
        startMaxDurationTimer()
    }

    private func startMaxDurationTimer() {
        maxDurationTimer = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.maxRecordingDuration))
                guard let self = self, !Task.isCancelled else { return }
                print("[Jetvoice] Max recording duration reached (\(Self.maxRecordingDuration / 60) minutes)")
                await self.triggerMaxDurationCallback()
            } catch {
                // Task was cancelled, which is fine
            }
        }
    }

    private func triggerMaxDurationCallback() {
        onMaxDurationReached?()
    }

    func stopRecording() throws -> Data {
        print("[Jetvoice] AudioRecorder.stopRecording called")

        // Cancel max duration timer
        maxDurationTimer?.cancel()
        maxDurationTimer = nil
        onMaxDurationReached = nil

        // Log recording duration
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print("[Jetvoice] Recording duration: \(String(format: "%.1f", duration)) seconds")
        }
        recordingStartTime = nil

        guard let engine = audioEngine, let fileURL = recordingURL else {
            print("[Jetvoice] ERROR: No recording available")
            throw RecorderError.noRecordingAvailable
        }

        print("[Jetvoice] Recording file URL: \(fileURL)")

        // Stop the tap and engine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        print("[Jetvoice] Audio engine stopped")

        // Clear references
        audioEngine = nil
        audioFile = nil

        // Read the recorded file
        let audioData = try Data(contentsOf: fileURL)
        print("[Jetvoice] Read audio file: \(audioData.count) bytes")

        // Clean up temp file
        try? FileManager.default.removeItem(at: fileURL)
        recordingURL = nil

        return audioData
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        guard let audioFile = audioFile else { return }

        // Calculate output buffer size based on sample rate ratio
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var error: NSError?
        var inputBuffer: AVAudioPCMBuffer? = buffer

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputBuffer != nil {
                outStatus.pointee = .haveData
                let result = inputBuffer
                inputBuffer = nil
                return result
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        guard status != .error, error == nil, outputBuffer.frameLength > 0 else { return }

        do {
            try audioFile.write(from: outputBuffer)
        } catch {
            print("Error writing audio buffer: \(error)")
        }
    }

    func isRecording() -> Bool {
        audioEngine != nil
    }
}
