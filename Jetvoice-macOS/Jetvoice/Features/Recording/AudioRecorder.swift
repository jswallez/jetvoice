//
//  AudioRecorder.swift
//  Jetvoice
//
//  AVAudioEngine-based audio recording with format conversion for Gemini API
//  Updated for macOS 15+ with proper cleanup
//

@preconcurrency import AVFoundation
import Foundation

/// Converts incoming microphone buffers to 16 kHz mono PCM16 and accumulates
/// them in memory, synchronously and in order, directly on the audio render
/// thread.
///
/// This is deliberately NOT actor-isolated: the input tap calls `append` on its
/// own real-time thread, one buffer at a time, in order. Doing the work inline
/// (rather than dispatching an async `Task` per buffer) removes two hazards that
/// the previous implementation had:
///   1. buffer reordering — independent `Task`s have no FIFO guarantee, so
///      writes could land out of order and scramble the audio;
///   2. buffer lifetime — the engine may recycle a buffer once the tap returns,
///      so deferring its read to a later Task was unsafe.
/// Accumulated PCM is guarded by a lock so the recorder thread (append) and the
/// caller thread (makeWAV) can't race. No temp file is touched.
nonisolated final class PCMRecorder: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()
    private var pcm = Data()

    init?(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    /// Called synchronously from the input tap (audio render thread).
    func append(_ buffer: AVAudioPCMBuffer) {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var error: NSError?
        var input: AVAudioPCMBuffer? = buffer
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if input != nil {
                outStatus.pointee = .haveData
                defer { input = nil }
                return input
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        guard status != .error, error == nil, out.frameLength > 0,
              let channel = out.int16ChannelData else { return }

        let frames = Int(out.frameLength)
        lock.lock()
        pcm.append(UnsafeBufferPointer(start: channel[0], count: frames))
        lock.unlock()
    }

    /// Snapshot the accumulated PCM as a complete in-memory WAV file.
    func makeWAV() -> Data {
        lock.lock()
        let body = pcm
        lock.unlock()
        return Self.wavData(
            pcm: body,
            sampleRate: Int(outputFormat.sampleRate),
            channels: Int(outputFormat.channelCount),
            bitsPerSample: 16
        )
    }

    /// Build a canonical 44-byte-header PCM WAV from raw little-endian samples.
    /// Pure function — unit tested.
    static func wavData(pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataLen = pcm.count

        var out = Data(capacity: 44 + dataLen)
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }

        out.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + dataLen))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        u32(16)                          // PCM fmt chunk size
        u16(1)                           // audio format = PCM
        u16(UInt16(channels))
        u32(UInt32(sampleRate))
        u32(UInt32(byteRate))
        u16(UInt16(blockAlign))
        u16(UInt16(bitsPerSample))
        out.append(contentsOf: Array("data".utf8))
        u32(UInt32(dataLen))
        out.append(pcm)
        return out
    }
}

actor AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var recorder: PCMRecorder?
    private var recordingStartTime: Date?
    private var maxDurationTimer: Task<Void, Never>?

    private let bufferSize: AVAudioFrameCount = 4096

    // Target format for Gemini API (16kHz mono for efficiency)
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    // Maximum recording duration (10 minutes) to stay within Gemini API limits
    // At 16kHz mono 16-bit, 10 minutes produces ~19MB.
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
        recorder = nil
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

        // Create output format (PCM 16-bit for WAV)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            throw RecorderError.formatConversionFailed
        }

        guard let recorder = PCMRecorder(inputFormat: inputFormat, outputFormat: outputFormat) else {
            throw RecorderError.formatConversionFailed
        }
        self.recorder = recorder

        // Install tap. The buffer is converted and appended SYNCHRONOUSLY on the
        // render thread (capturing `recorder` directly, not via the actor) so
        // writes stay strictly in order and the buffer is consumed before the
        // engine can recycle it.
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { buffer, _ in
            recorder.append(buffer)
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

    func stopRecording() async throws -> Data {
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

        guard let engine = audioEngine, let recorder = recorder else {
            print("[Jetvoice] ERROR: No recording available")
            throw RecorderError.noRecordingAvailable
        }

        // Stop the tap and engine. After removeTap returns, no further `append`
        // calls happen; the last in-flight call (if any) completes synchronously
        // on the render thread, so the accumulated PCM is final here.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        print("[Jetvoice] Audio engine stopped")

        audioEngine = nil
        self.recorder = nil

        let audioData = recorder.makeWAV()
        print("[Jetvoice] Built in-memory WAV: \(audioData.count) bytes")
        return audioData
    }

    func isRecording() -> Bool {
        audioEngine != nil
    }
}
