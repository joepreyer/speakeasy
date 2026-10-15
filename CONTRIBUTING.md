# Contributing to SpeakEasy

Thanks for helping out. Bug fixes, new features, and docs improvements are all welcome.

## Setup

You need macOS 13+, Xcode 15+ (or its command line tools with Swift 5.9+), and an OpenAI API key.

```bash
git clone https://github.com/joepreyer/speakeasy.git
cd speakeasy
scripts/setup-dev-signing.sh   # once; asks for your password
./build.sh
open build/SpeakEasy.app
```

`setup-dev-signing.sh` creates a local signing certificate so macOS keeps SpeakEasy's permissions between builds. Without it, every rebuild counts as a new app and you'll be asked to grant Accessibility and Input Monitoring again.

If you already have the release version installed, quit it first so you don't run two copies.

## Testing

```bash
swift test
```

To try the transcription and formatting pipeline without a microphone, run the app binary on an audio file (uses the API key saved by the app):

```bash
say -o sample.m4a "um let's meet at 2, actually 3"
build/SpeakEasy.app/Contents/MacOS/SpeakEasy --dictate-file sample.m4a --app com.apple.Notes
```

Pass `--app <bundle id>` to format as if dictating into that app (for example `com.todesktop.230313mzl4w4u92` for Cursor) and `--workspace <folder>` to test file tagging.

## Project layout

| Path | What's there |
| --- | --- |
| `Sources/SpeakEasy/AppDelegate.swift` | The dictation flow: fn down, record, transcribe, format, paste |
| `Sources/SpeakEasy/Formatter.swift` | The formatting prompt |
| `Sources/SpeakEasy/AppContext.swift` | Frontmost app, developer mode, workspace file detection |
| `Sources/SpeakEasy/CorrectionLearner.swift` | Learning dictionary words from spelling fixes |
| `Sources/SpeakEasy/Onboarding.swift` | The setup assistant |
| `Sources/SpeakEasy/MainWindow.swift` | History, dictionary, and settings window |
| `scripts/` | Install, uninstall, packaging, icon generation |

## Pull requests

- Keep each PR focused on one change, and describe how you tested it.
- `swift test` must pass. CI runs it on every PR.
- For UI changes, include a screenshot.
- If you change the formatting prompt, include a few before/after examples from `--dictate-file`.

The `main` branch is protected, and a maintainer reviews and merges every PR.

## Releasing (maintainers)

Push a version tag and GitHub Actions builds, packages, and publishes the release:

```bash
git tag v1.1.0
git push origin v1.1.0
```

Releases are ad-hoc signed by default. To sign and notarize them, add these repository secrets: `MACOS_CERTIFICATE_P12` (base64-encoded Developer ID Application certificate), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, and `NOTARY_PASSWORD` (an app-specific password).
