#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
APP_PATH="$HOME/Applications/Codex Quota.app"

swift build --package-path "$ROOT" -c release
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$ROOT/.build/release/CodexQuota" "$APP_PATH/Contents/MacOS/CodexQuota"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Codex Quota</string>
    <key>CFBundleExecutable</key>
    <string>CodexQuota</string>
    <key>CFBundleIdentifier</key>
    <string>ru.zulut.codexquota</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Codex Quota</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

open "$APP_PATH"
