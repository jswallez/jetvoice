# Jetvoice

**Fast, precise voice-to-text for macOS** - A menu bar app that transcribes your voice anywhere on your Mac using Google Gemini AI.

## Features

- **Global Hotkey** - Push-to-talk recording from anywhere (default: Ctrl+Shift+Space)
- **Instant Transcription** - Powered by Google Gemini 2.5/3.0 Flash
- **Automatic Text Injection** - Transcribed text appears at your cursor
- **Multi-Language Support** - Automatic language detection
- **BYOK Model** - Bring Your Own Key (use your Gemini API key)
- **Privacy First** - No data stored on servers; audio processed via Gemini API only
- **Audio Feedback** - Optional sounds for recording/transcription events

## Requirements

- **macOS 15.0** (Sequoia) or later
- **Xcode 15+** (for building from source)
- **Google Gemini API Key** ([Get one here](https://aistudio.google.com/apikey))

## Installation

### Download (Recommended)

Download the latest DMG from [GitHub Releases](https://github.com/jswallez/jetvoice/releases).

1. Open the DMG
2. Drag Jetvoice to Applications
3. Launch from Applications
4. Follow the onboarding to grant permissions and enter your API key

### Build from Source

```bash
git clone https://github.com/jswallez/jetvoice.git
cd jetvoice/Jetvoice-macOS
open Jetvoice.xcodeproj
```

1. Open in Xcode
2. Select your Development Team in Signing & Capabilities
3. Build and Run (Cmd+R)

> **Note for contributors:** You must use your own Apple Developer Team ID for code signing. Update the `DEVELOPMENT_TEAM` in Xcode's Signing & Capabilities settings.

## Required Permissions

Jetvoice requires these permissions to function:

| Permission | Purpose |
|------------|---------|
| **Microphone** | Record your voice for transcription |
| **Accessibility** | Type transcribed text at cursor position |
| **Input Monitoring** | Detect global hotkey presses |

## Usage

1. **Press your hotkey** (default: Ctrl+Shift+Space) to start recording
2. **Speak** - your voice is recorded
3. **Release the hotkey** - audio is sent to Gemini for transcription
4. **Text appears** - transcription is typed at your cursor

### Tips

- Press hotkey again during processing to cancel
- If you switch apps during transcription, text is copied to clipboard instead
- Customize hotkey and sounds in Settings

## Project Structure

```
Jetvoice-macOS/
├── Jetvoice/
│   ├── App/              # App entry point, AppDelegate
│   ├── Features/         # Core features
│   │   ├── Recording/    # Audio recording
│   │   ├── Transcription/# Gemini API client
│   │   ├── HotKey/       # Global hotkey handling
│   │   ├── TextInjection/# Text insertion at cursor
│   │   └── Feedback/     # Sound effects
│   ├── Services/         # Shared services (permissions)
│   └── Views/            # SwiftUI views
├── design/               # Icons, logos, sounds
└── docs/                 # Documentation
```

## Tech Stack

- **Swift 5.0** with modern concurrency (async/await, actors)
- **AppKit** for menu bar integration
- **SwiftUI** for settings and popover views
- **Security.framework** for Keychain API key storage
- **AVFoundation** for audio recording

## API Key Storage

Your Gemini API key is stored securely in the macOS Keychain. It never leaves your device except when making API calls to Google.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting PRs.

## Security

For security concerns, please see [SECURITY.md](SECURITY.md).

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Built by [@jswallez](https://x.com/jswallez)
