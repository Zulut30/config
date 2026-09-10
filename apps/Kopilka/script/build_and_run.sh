#!/bin/bash
set -euo pipefail
KOPILKA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KOPILKA_ROOT"
MODE="${1:-run}"
case "$MODE" in run|--build-only|--verify|--logs|--debug) ;; *) printf 'Usage: %s [--build-only|--verify|--logs|--debug]\n' "$0"; exit 2;; esac
if /usr/bin/pgrep -x Kopilka >/dev/null; then /usr/bin/pkill -TERM -x Kopilka; fi
/usr/bin/xcrun swift build
KOPILKA_BIN="$(/usr/bin/xcrun swift build --show-bin-path)/Kopilka"
KOPILKA_BUNDLE="$KOPILKA_ROOT/dist/Kopilka.app"
mkdir -p "$KOPILKA_BUNDLE/Contents/MacOS" "$KOPILKA_BUNDLE/Contents/Resources"
cp "$KOPILKA_BIN" "$KOPILKA_BUNDLE/Contents/MacOS/Kopilka"
cp "$KOPILKA_ROOT/Resources/Info.plist" "$KOPILKA_BUNDLE/Contents/Info.plist"
if [ ! -f "$KOPILKA_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    /usr/bin/xcrun swift "$KOPILKA_ROOT/script/generate_icon.swift" "$KOPILKA_ROOT/dist/AppIcon.iconset"
    /usr/bin/iconutil -c icns "$KOPILKA_ROOT/dist/AppIcon.iconset" -o "$KOPILKA_BUNDLE/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --sign - --identifier ru.zulut.kopilka --requirements '=designated => identifier "ru.zulut.kopilka";' "$KOPILKA_BUNDLE"
if [ "$MODE" = '--build-only' ]; then exit 0; fi
KOPILKA_INSTALL="/Users/zulut/Applications/Kopilka.app"
if [ -e "$KOPILKA_INSTALL" ]; then
    KOPILKA_EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$KOPILKA_INSTALL/Contents/Info.plist")
    if [ "$KOPILKA_EXISTING_ID" != 'ru.zulut.kopilka' ]; then printf 'Destination contains a different app.\n' >&2; exit 1; fi
fi
mkdir -p /Users/zulut/Applications
/usr/bin/ditto "$KOPILKA_BUNDLE" "$KOPILKA_INSTALL"
if [ "$MODE" = '--debug' ]; then exec /usr/bin/xcrun lldb -- "$KOPILKA_INSTALL/Contents/MacOS/Kopilka"; fi
/usr/bin/open "$KOPILKA_INSTALL"
if [ "$MODE" = '--verify' ]; then
    for attempt in 1 2 3 4 5; do
        if /usr/bin/pgrep -x Kopilka >/dev/null; then printf 'Kopilka launched successfully.\n'; exit 0; fi
        sleep 1
    done
    exit 1
fi
if [ "$MODE" = '--logs' ]; then exec /usr/bin/log stream --style compact --info --predicate 'process == "Kopilka"'; fi
