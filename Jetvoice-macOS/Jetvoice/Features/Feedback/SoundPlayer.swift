//
//  SoundPlayer.swift
//  Jetvoice
//
//  Sound player for transcription complete feedback
//

import AppKit

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Sound player for transcription feedback
final class SoundPlayer: @unchecked Sendable {
    private var transcribedSound: NSSound?
    private var cancelSound: NSSound?
    private var stopSound: NSSound?

    private var userVolume: Float {
        let stored = UserDefaults.standard.double(forKey: "soundVolume")
        // Default to 0.6 (middle level) if not set
        let volume = stored > 0 ? stored : 0.6
        return Float(volume.clamped(to: 0.2...1.0))
    }

    init() {
        loadSounds()
    }

    private func loadSounds() {
        if let url = Bundle.main.url(forResource: "jetvoice-transcribed", withExtension: "wav") {
            transcribedSound = NSSound(contentsOf: url, byReference: false)
            print("[SoundPlayer] Loaded transcribed sound")
        } else {
            print("[SoundPlayer] ERROR: Could not find jetvoice-transcribed.wav")
        }

        if let url = Bundle.main.url(forResource: "jetvoice-cancel", withExtension: "wav") {
            cancelSound = NSSound(contentsOf: url, byReference: false)
            print("[SoundPlayer] Loaded cancel sound")
        } else {
            print("[SoundPlayer] WARNING: Could not find jetvoice-cancel.wav")
        }

        if let url = Bundle.main.url(forResource: "jetvoice-stop", withExtension: "wav") {
            stopSound = NSSound(contentsOf: url, byReference: false)
            print("[SoundPlayer] Loaded stop sound")
        } else {
            print("[SoundPlayer] WARNING: Could not find jetvoice-stop.wav")
        }
    }

    func playTranscribedSound() {
        guard let sound = transcribedSound else {
            print("[SoundPlayer] No transcribed sound")
            return
        }

        if sound.isPlaying {
            sound.stop()
        }

        sound.volume = userVolume
        sound.play()
        print("[SoundPlayer] Playing transcribed sound...")
    }

    func playCancelSound() {
        guard let sound = cancelSound else {
            print("[SoundPlayer] No cancel sound")
            return
        }

        if sound.isPlaying {
            sound.stop()
        }

        sound.volume = userVolume
        sound.play()
        print("[SoundPlayer] Playing cancel sound...")
    }

    /// Play sound when recording is auto-stopped (e.g., max duration reached)
    func playStopSound() {
        guard let sound = stopSound else {
            print("[SoundPlayer] No stop sound")
            return
        }

        if sound.isPlaying {
            sound.stop()
        }

        sound.volume = userVolume
        sound.play()
        print("[SoundPlayer] Playing stop sound...")
    }
}
