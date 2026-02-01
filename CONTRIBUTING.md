# Contributing to Jetvoice

Thank you for your interest in contributing to Jetvoice! This document provides guidelines for contributing.

## Getting Started

### Prerequisites

- macOS 15.0 or later
- Xcode 15 or later
- A Google Gemini API key (for testing)
- An Apple Developer account (for code signing)

### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/jetvoice.git
   cd jetvoice/Jetvoice-macOS
   ```
3. Open `Jetvoice.xcodeproj` in Xcode
4. Select your Development Team in Signing & Capabilities
5. Build and run

### Development Notes

- The project uses pure AppKit for the menu bar with SwiftUI for views
- API keys are stored in Keychain, never in code
- Audio is recorded at 16kHz mono for optimal transcription

## Making Changes

### Branching Strategy

- Create feature branches from `main`
- Use descriptive branch names: `feature/add-model-selection`, `fix/hotkey-detection`

### Code Style

- Follow existing code conventions
- Use Swift's modern concurrency patterns (async/await)
- Add comments for complex logic
- Keep functions focused and small

### Testing

- Test on macOS 15.0 minimum
- Verify all permissions work correctly
- Test with various recording lengths
- Test hotkey behavior in different apps

## Submitting Changes

### Pull Request Process

1. Ensure your code builds without warnings
2. Test your changes thoroughly
3. Update documentation if needed
4. Create a pull request with:
   - Clear title describing the change
   - Description of what and why
   - Screenshots for UI changes
   - Testing notes

### Commit Messages

Use clear, descriptive commit messages:

- `feat: add support for Gemini 3.0 model`
- `fix: resolve hotkey not working in Finder`
- `docs: update README with build instructions`
- `refactor: simplify audio recording pipeline`

## Reporting Issues

### Bug Reports

Include:

- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Console logs if available

### Feature Requests

- Describe the use case
- Explain why it would benefit users
- Consider implementation complexity

## Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Questions?

Open a discussion or issue on GitHub.

---

Thank you for helping make Jetvoice better!
