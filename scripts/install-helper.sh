#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${APPSNAP_APP_DIR:-$HOME/.local/Applications/Appsnap.app}"
BIN_DIR="${APPSNAP_BIN_DIR:-$HOME/.local/bin}"
APP_BIN="$APP_DIR/Contents/MacOS/appsnap"

cd "$ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$BIN_DIR"
install -m 755 ".build/release/appsnap" "$APP_BIN"
install -m 644 "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier dev.fulldotdev.appsnap "$APP_DIR"
ln -sfn "$APP_BIN" "$BIN_DIR/appsnap"

printf 'Installed Appsnap helper app at %s\n' "$APP_DIR"
printf 'Linked CLI at %s\n' "$BIN_DIR/appsnap"
printf 'No Developer ID signing, notarization, or Apple Developer account is used.\n'
