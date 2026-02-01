# Open Source Release Guide

This document describes how to prepare the Jetvoice repository for public release.

## Repository

Single public repo: **`jswallez/jetvoice`**

## Before Making Public

### 1. Change Bundle ID (optional)

If you want to change the bundle ID from `ai.jetvoice.app` to `com.jswallez.Jetvoice`:

1. Open Xcode project
2. Select the target > Signing & Capabilities
3. Change Bundle Identifier to `com.jswallez.Jetvoice`
4. Update Keychain service name in `GeminiService.swift` (line ~31)

**Note:** This is best done before public release. After release, changing the bundle ID will:
- Require users to re-grant all permissions (Accessibility, Input Monitoring, Microphone)
- Not transfer Keychain-stored API keys
- Not transfer UserDefaults preferences

### 2. Squash commits (optional)

If you want a clean history without development commits:

```bash
# Create a new branch with squashed history
git checkout --orphan clean-main
git add -A
git commit -m "Initial commit"

# Replace main with clean history
git branch -D main
git branch -m main

# Force push (CAREFUL - rewrites history)
git push --force origin main
```

### 3. Add README.md

Create a `README.md` in the repo root with:

- App description and screenshot
- Features list
- Requirements (macOS 15+, Gemini API key)
- Installation instructions (download DMG from Releases)
- Building from source instructions
- License (MIT)

### 4. Add LICENSE

```bash
# Download MIT License template
curl -o LICENSE https://opensource.org/licenses/MIT
# Edit to add: Copyright (c) 2025 Sylvain Wallez
```

### 5. Add Privacy Policy and Terms (GitHub Pages)

Create files in `docs/` folder for GitHub Pages:

```
docs/
├── privacy.md      # Privacy policy
└── terms.md        # Terms of service
```

Enable GitHub Pages in repo settings:
- Source: Deploy from a branch
- Branch: main, folder: /docs

URLs will be:
- `https://jswallez.github.io/jetvoice/privacy`
- `https://jswallez.github.io/jetvoice/terms`

Update the links in `SettingsView.swift` About tab.

### 6. Review .gitignore

Make sure these are gitignored:
- `credentials/` - API keys
- `.env` files
- Build artifacts (`.app`, `.dmg`)
- Xcode user data

### 7. Make repo public

Go to GitHub repo settings > Danger Zone > Change visibility > Make public

## After Making Public

### Create first release

```bash
# Tag the release
git tag v1.0.0
git push origin v1.0.0

# Build, notarize, and create DMG (see CLAUDE.md)

# Create release with DMG
gh release create v1.0.0 Jetvoice.dmg \
  --title "Jetvoice v1.0.0" \
  --notes "Initial public release"
```

### Optional: GitHub Sponsors / Ko-fi

Add funding links to accept donations:

1. Create `.github/FUNDING.yml`:
   ```yaml
   github: jswallez
   ko_fi: jswallez
   ```

2. This adds a "Sponsor" button to the repo
