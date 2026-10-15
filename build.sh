#!/bin/bash
# Development build for this Mac's architecture: build/SpeakEasy.app
# For a universal, distributable build use scripts/package.sh.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/SpeakEasy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SpeakEasy "$APP/Contents/MacOS/SpeakEasy"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"

# A stable identity keeps macOS permissions across rebuilds (see scripts/setup-dev-signing.sh).
IDENTITY="${SIGNING_IDENTITY:-SpeakEasy Dev Signing}"
if [ "$IDENTITY" != "-" ] && security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --entitlements SpeakEasy.entitlements "$APP"
else
    echo "note: signing ad-hoc, so macOS permissions reset on every rebuild."
    echo "      Run scripts/setup-dev-signing.sh once to fix that."
    codesign --force --sign - --entitlements SpeakEasy.entitlements "$APP"
fi

echo
echo "Built $APP"
echo "Run with: open $APP"
