#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

pkill -f '/GeoArtLab.app/Contents/MacOS/GeoArtLab' >/dev/null 2>&1 || true
pkill -f '/.build/arm64-apple-macosx/debug/GeoArtLab' >/dev/null 2>&1 || true

swift build
BIN_DIR="$(swift build --show-bin-path)"
APP_DIR="$SCRIPT_DIR/.run/GeoArtLab.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"
cp "$BIN_DIR/GeoArtLab" "$MACOS_DIR/GeoArtLab"
chmod +x "$MACOS_DIR/GeoArtLab"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>GeoArtLab</string>
  <key>CFBundleDisplayName</key>
  <string>GeoArtLab</string>
  <key>CFBundleIdentifier</key>
  <string>com.joebot.geoartlab</string>
  <key>CFBundleExecutable</key>
  <string>GeoArtLab</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

open -na "$APP_DIR"
