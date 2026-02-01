# Jetvoice

Jetvoice is a voice-to-text transcription app that lets users dictate text anywhere on their device using a global hotkey.

## Repository

Single public repo: **`jswallez/jetvoice`**

Local folder structure:
```
Development/                  # Repo root (jswallez/jetvoice)
├── Jetvoice-macOS/           # macOS menu bar app (Swift/AppKit)
├── design/                   # Design assets (icons, logos, sounds)
├── docs/                     # Documentation
└── credentials/              # API keys and secrets (gitignored)
```

## Jetvoice-macOS

A macOS menu bar application built with Swift and AppKit.

### Key Features
- Global hotkey for push-to-talk recording (customizable)
- Voice transcription using Google Gemini API (BYOK - Bring Your Own Key)
- Automatic text injection into the active text field
- Menu bar icon with status indicators (recording, processing, error)
- Model selection (Gemini 2.5 Flash / 3.0 Flash)
- Custom feedback sounds with volume control
- Cancel transcription by pressing hotkey again
- Onboarding flow for permissions and API key setup

### Tech Stack
- Swift / AppKit (pure AppKit, no SwiftUI App lifecycle)
- NSStatusItem for menu bar presence
- Keychain for secure API key storage
- Google Gemini API for transcription

### Architecture
- `App/` - App entry point and AppDelegate
- `Features/` - Feature modules (Recording, Transcription, HotKey, TextInjection)
- `Services/` - Shared services (PermissionManager, SoundPlayer)
- `Views/` - SwiftUI views for popover, settings, onboarding

### Required Permissions
- Microphone access (for recording)
- Accessibility access (for text injection)
- Input Monitoring (for global hotkey)

### Building
Open `Jetvoice-macOS/Jetvoice.xcodeproj` in Xcode and build.

### Distribution (Notarized, outside App Store)

The app requires Accessibility and Input Monitoring permissions which are incompatible with App Store sandboxing. It must be distributed as a notarized app outside the App Store.

#### Prerequisites
1. Apple Developer account ($99/year)
2. Developer ID Application certificate (create in Xcode or developer.apple.com)
3. App-specific password for notarytool (create at appleid.apple.com > Security > App-Specific Passwords)

#### Build & Notarize Steps

1. **Archive the app in Xcode:**
   - Product > Archive
   - Select "Developer ID" distribution (NOT App Store)
   - Export the .app

2. **Create a DMG (optional but recommended):**
   ```bash
   hdiutil create -volname "Jetvoice" -srcfolder Jetvoice.app -ov -format UDZO Jetvoice.dmg
   ```

3. **Notarize the app/DMG:**
   ```bash
   # Store credentials (one time)
   xcrun notarytool store-credentials "notary-profile" \
     --apple-id "your@email.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "app-specific-password"

   # Submit for notarization
   xcrun notarytool submit Jetvoice.dmg --keychain-profile "notary-profile" --wait

   # Staple the ticket (attaches notarization to the file)
   xcrun stapler staple Jetvoice.dmg
   ```

4. **Verify notarization:**
   ```bash
   spctl -a -vvv -t install Jetvoice.app
   ```

#### Distribution via GitHub Releases

The app is distributed via GitHub Releases on `jswallez/jetvoice`.

**Why DMG instead of .app?**
- `.app` is a folder bundle - harder to distribute and may trigger "app is damaged" warnings
- `.dmg` is a disk image - standard Mac distribution format outside the App Store
- Notarization tickets staple better to DMG files
- Users expect DMG: open it, drag app to Applications, done

**Release Process:**

1. **Build & Export:**
   - In Xcode: Product > Archive
   - Distribute App > Developer ID > Export
   - This creates a signed `Jetvoice.app`

2. **Create DMG:**
   ```bash
   hdiutil create -volname "Jetvoice" -srcfolder Jetvoice.app -ov -format UDZO Jetvoice.dmg
   ```

3. **Notarize & Staple:**
   ```bash
   xcrun notarytool submit Jetvoice.dmg --keychain-profile "notary-profile" --wait
   xcrun stapler staple Jetvoice.dmg
   ```

4. **Create GitHub Release:**
   ```bash
   # Tag the release
   git tag v1.0.0
   git push origin v1.0.0

   # Create release and upload DMG
   gh release create v1.0.0 Jetvoice.dmg \
     --title "Jetvoice v1.0.0" \
     --notes "Release notes here..."
   ```

**Important:** Never commit `.app` or `.dmg` files to git. They belong in GitHub Releases (artifact storage), not in the repository history.
