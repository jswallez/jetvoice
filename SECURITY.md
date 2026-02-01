# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Email the maintainer directly or use GitHub's private vulnerability reporting
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will respond within 48 hours and work with you to address the issue.

## Security Architecture

### API Key Storage

- Gemini API keys are stored in the macOS Keychain
- Keys are never logged or transmitted except to the Gemini API
- Keys are never stored in UserDefaults or plain text files

### Network Security

- All API communication uses HTTPS
- No telemetry or analytics are collected
- Audio data is sent only to Google's Gemini API

### Permissions

| Permission | Purpose | Data Access |
|------------|---------|-------------|
| Microphone | Voice recording | Audio captured only while hotkey is held |
| Accessibility | Text injection | Used to type at cursor; no screen reading |
| Input Monitoring | Hotkey detection | Only monitors configured hotkey combination |

### Data Privacy

- No audio or transcription data is stored locally after processing
- No data is sent to any servers besides the Gemini API
- The app operates entirely offline except for transcription API calls
- No user accounts or registration required

## Best Practices for Users

1. **Protect your API key** - Don't share it; it's tied to your billing account
2. **Review permissions** - Grant only when you understand why they're needed
3. **Keep updated** - Install updates for security fixes
4. **Monitor API usage** - Check your Google Cloud console for unexpected usage

## Dependency Security

This project uses minimal external dependencies:

- **No third-party Swift packages** - All functionality uses Apple frameworks
- **Apple frameworks only**: AppKit, SwiftUI, Security, AVFoundation

## Secure Development

Contributors should:

- Never commit API keys, tokens, or secrets
- Use environment variables or Keychain for sensitive data
- Review code for common vulnerabilities (injection, data exposure)
- Test permission handling edge cases
