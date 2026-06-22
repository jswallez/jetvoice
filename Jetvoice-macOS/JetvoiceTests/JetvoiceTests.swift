//
//  JetvoiceTests.swift
//  JetvoiceTests
//
//  Unit tests for the pure, side-effect-free logic that's easy to get subtly
//  wrong: WAV framing, hotkey config (de)serialization, and error messaging.
//

import XCTest
@testable import Jetvoice

@MainActor
final class JetvoiceTests: XCTestCase {

    // MARK: - PCMRecorder.wavData

    func testWavHeaderStructure() throws {
        // 4 stereo-less Int16 samples = 8 bytes of PCM.
        let pcm = Data([0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00])
        let wav = PCMRecorder.wavData(pcm: pcm, sampleRate: 16000, channels: 1, bitsPerSample: 16)

        // 44-byte header + body.
        XCTAssertEqual(wav.count, 44 + pcm.count)

        func ascii(_ range: Range<Int>) -> String {
            String(decoding: wav[range], as: UTF8.self)
        }
        XCTAssertEqual(ascii(0..<4), "RIFF")
        XCTAssertEqual(ascii(8..<12), "WAVE")
        XCTAssertEqual(ascii(12..<16), "fmt ")
        XCTAssertEqual(ascii(36..<40), "data")

        func u32(_ offset: Int) -> UInt32 {
            wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
        }
        func u16(_ offset: Int) -> UInt16 {
            wav.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
        }

        XCTAssertEqual(u32(4), UInt32(36 + pcm.count))   // RIFF chunk size
        XCTAssertEqual(u32(16), 16)                       // PCM fmt chunk size
        XCTAssertEqual(u16(20), 1)                        // audio format = PCM
        XCTAssertEqual(u16(22), 1)                        // channels
        XCTAssertEqual(u32(24), 16000)                    // sample rate
        XCTAssertEqual(u32(28), 16000 * 1 * 16 / 8)       // byte rate
        XCTAssertEqual(u16(32), 1 * 16 / 8)               // block align
        XCTAssertEqual(u16(34), 16)                       // bits per sample
        XCTAssertEqual(u32(40), UInt32(pcm.count))        // data chunk size

        // Body bytes are preserved verbatim after the header.
        XCTAssertEqual(Array(wav.suffix(pcm.count)), Array(pcm))
    }

    func testWavEmptyBodyStillHasValidHeader() {
        let wav = PCMRecorder.wavData(pcm: Data(), sampleRate: 16000, channels: 1, bitsPerSample: 16)
        XCTAssertEqual(wav.count, 44)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
    }

    // MARK: - HotKeyConfiguration

    func testHotKeyConfigRoundTrip() throws {
        let config = HotKeyConfiguration(keyCode: 49, modifiers: 0x80000, isModifierOnly: false)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HotKeyConfiguration.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testHotKeyConfigBackwardCompatDecode() throws {
        // Older saved configs lack `isModifierOnly`; it must default to false.
        let json = #"{"keyCode": 49, "modifiers": 524288}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HotKeyConfiguration.self, from: json)
        XCTAssertEqual(decoded.keyCode, 49)
        XCTAssertEqual(decoded.modifiers, 524288)
        XCTAssertFalse(decoded.isModifierOnly)
    }

    func testDefaultHotKeyIsModifierOnly() {
        XCTAssertTrue(HotKeyConfiguration.defaultHotKey.isModifierOnly)
        XCTAssertFalse(HotKeyConfiguration.defaultHotKey.displayString.isEmpty)
    }

    // MARK: - AppError

    func testAllAppErrorsHaveDescriptions() {
        let errors: [AppError] = [
            .microphonePermissionDenied,
            .accessibilityPermissionDenied,
            .recordingFailed("x"),
            .transcriptionFailed("y"),
            .noAudioRecorded
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "Missing description for \(error)")
            XCTAssertFalse(error.id.isEmpty)
        }
    }
}
