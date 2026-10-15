#!/bin/bash
# Builds a universal SpeakEasy.app and packages it as dist/SpeakEasy.zip and dist/SpeakEasy.dmg.
#
# Usage: scripts/package.sh [version]
#   SIGNING_IDENTITY  codesign identity (default: "-", ad-hoc). A Developer ID identity also
#                     enables the hardened runtime, which notarization requires.
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
#                     when set (with a Developer ID identity), notarizes and staples the app and DMG.
#                     NOTARY_PASSWORD is an app-specific password from appleid.apple.com.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="${SIGNING_IDENTITY:--}"
OUT="dist"
APP="$OUT/SpeakEasy.app"

echo "==> Building SpeakEasy $VERSION ($BUILD_NUMBER), universal"
swift build -c release --arch arm64 --arch x86_64

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/SpeakEasy "$APP/Contents/MacOS/SpeakEasy"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

echo "==> Signing with identity: $IDENTITY"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - --entitlements SpeakEasy.entitlements "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements SpeakEasy.entitlements "$APP"
fi
codesign --verify --strict "$APP"

NOTARIZE=""
if [ "$IDENTITY" != "-" ] && [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    NOTARIZE="yes"
fi
notarize() {
    xcrun notarytool submit "$1" --wait \
        --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD"
}

echo "==> Creating SpeakEasy.zip"
ditto -c -k --keepParent "$APP" "$OUT/SpeakEasy.zip"
if [ -n "$NOTARIZE" ]; then
    echo "==> Notarizing the app"
    notarize "$OUT/SpeakEasy.zip"
    xcrun stapler staple "$APP"
    rm "$OUT/SpeakEasy.zip"
    ditto -c -k --keepParent "$APP" "$OUT/SpeakEasy.zip"
fi

echo "==> Creating SpeakEasy.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/SpeakEasy.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "SpeakEasy" -srcfolder "$STAGING" -ov -format UDZO "$OUT/SpeakEasy.dmg"
if [ "$IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$OUT/SpeakEasy.dmg"
fi
if [ -n "$NOTARIZE" ]; then
    echo "==> Notarizing the DMG"
    notarize "$OUT/SpeakEasy.dmg"
    xcrun stapler staple "$OUT/SpeakEasy.dmg"
fi

echo
echo "Packaged:"
ls -lh "$OUT/SpeakEasy.zip" "$OUT/SpeakEasy.dmg"
