#!/bin/bash
# Installs the latest SpeakEasy release into Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/joepreyer/speakeasy/main/scripts/install.sh | bash
#
# SPEAKEASY_DOWNLOAD_URL overrides where the release zip comes from (any URL curl accepts).
set -euo pipefail

REPO="joepreyer/speakeasy"
BUNDLE_ID="io.github.joepreyer.speakeasy"
URL="${SPEAKEASY_DOWNLOAD_URL:-https://github.com/$REPO/releases/latest/download/SpeakEasy.zip}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "SpeakEasy only runs on macOS."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 13 ] || fail "SpeakEasy needs macOS 13 (Ventura) or later."

if [ -w /Applications ]; then
    DEST_DIR="/Applications"
else
    DEST_DIR="$HOME/Applications"
    mkdir -p "$DEST_DIR"
fi
DEST="$DEST_DIR/SpeakEasy.app"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bold "Downloading SpeakEasy…"
curl -fL --progress-bar "$URL" -o "$TMP/SpeakEasy.zip" || fail "Download failed. Check your connection and try again."

ditto -x -k "$TMP/SpeakEasy.zip" "$TMP"
[ -d "$TMP/SpeakEasy.app" ] || fail "The download didn't contain SpeakEasy.app."
codesign --verify --strict "$TMP/SpeakEasy.app" 2>/dev/null || fail "The downloaded app failed its code signature check."

if pgrep -x SpeakEasy >/dev/null; then
    bold "Closing the running copy of SpeakEasy…"
    pkill -x SpeakEasy || true
    sleep 1
fi

bold "Installing to ${DEST_DIR}…"
REPLACING=""
[ -d "$DEST" ] && REPLACING="yes"
rm -rf "$DEST"
ditto "$TMP/SpeakEasy.app" "$DEST"

# Ad-hoc builds get a new signature every release, so permissions saved for the old copy
# show as switched on in System Settings but don't apply. Clear them so setup starts clean.
SIGNATURE="$(codesign -dv "$DEST" 2>&1 || true)"
if [ -n "$REPLACING" ] && [[ "$SIGNATURE" == *"Signature=adhoc"* ]]; then
    for service in Accessibility ListenEvent Microphone; do
        tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
    done
fi

open "$DEST"
echo
bold "✓ SpeakEasy is installed."
echo "  Follow the setup window to finish. After that, hold fn anywhere to dictate."
