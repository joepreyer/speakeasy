#!/bin/bash
# Removes SpeakEasy, its login item, and its macOS permissions.
#
#   curl -fsSL https://raw.githubusercontent.com/joepreyer/speakeasy/main/scripts/uninstall.sh | bash
#
# --purge      also delete history, dictionary, settings, and the saved API key
# --keep-data  keep them without asking
set -euo pipefail

BUNDLE_ID="io.github.joepreyer.speakeasy"
DATA_DIR="$HOME/Library/Application Support/SpeakEasy"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

PURGE=""
case "${1:-}" in
    --purge) PURGE="yes" ;;
    --keep-data) PURGE="no" ;;
esac

if [ -z "$PURGE" ]; then
    if [ -r /dev/tty ] && (exec </dev/tty) 2>/dev/null; then
        printf "Also delete your dictation history, dictionary, settings, and saved API key? [y/N] "
        read -r answer </dev/tty || answer=""
        case "$answer" in [yY]*) PURGE="yes" ;; *) PURGE="no" ;; esac
    else
        PURGE="no"
    fi
fi

APPS=()
for candidate in "/Applications/SpeakEasy.app" "$HOME/Applications/SpeakEasy.app"; do
    [ -d "$candidate" ] && APPS+=("$candidate")
done

for app in "${APPS[@]+"${APPS[@]}"}"; do
    "$app/Contents/MacOS/SpeakEasy" --unregister-login-item 2>/dev/null || true
done

if pgrep -x SpeakEasy >/dev/null; then
    bold "Quitting SpeakEasy…"
    pkill -x SpeakEasy || true
    sleep 1
fi

for app in "${APPS[@]+"${APPS[@]}"}"; do
    bold "Removing ${app}…"
    rm -rf "$app"
done

bold "Removing permissions…"
for service in Accessibility ListenEvent Microphone; do
    tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
done

if [ "$PURGE" = "yes" ]; then
    bold "Deleting history, dictionary, settings, and API key…"
    rm -rf "$DATA_DIR"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    security delete-generic-password -s "$BUNDLE_ID" -a openai_api_key >/dev/null 2>&1 || true
else
    echo "Kept your history, dictionary, settings, and API key. Run with --purge to delete them."
fi

echo
bold "✓ SpeakEasy is uninstalled."
