#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${APPSNAP_APP_DIR:-$HOME/Applications/Appsnap.app}"
OLD_APP_DIR="$HOME/.local/Applications/Appsnap.app"
BIN_DIR="${APPSNAP_BIN_DIR:-$HOME/.local/bin}"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/dev.fulldotdev.appsnap.plist"
LAUNCH_LABEL="dev.fulldotdev.appsnap"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/Appsnap.log"
APP_BIN="$APP_DIR/Contents/MacOS/appsnap"
GUI_DOMAIN="gui/$(id -u)"

cd "$ROOT"
swift build -c release

/bin/launchctl bootout "$GUI_DOMAIN/$LAUNCH_LABEL" 2>/dev/null || true
/usr/bin/pkill -x appsnap 2>/dev/null || true

rm -rf "$APP_DIR"
if [[ "$OLD_APP_DIR" != "$APP_DIR" ]]; then
  rm -rf "$OLD_APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$BIN_DIR" "$LAUNCH_AGENT_DIR" "$LOG_DIR"
install -m 755 ".build/release/appsnap" "$APP_BIN"
install -m 644 "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier dev.fulldotdev.appsnap "$APP_DIR"
ln -sfn "$APP_BIN" "$BIN_DIR/appsnap"
/usr/bin/sed \
  -e "s#__APPSNAP_BINARY__#$APP_BIN#g" \
  -e "s#__APPSNAP_LOG__#$LOG_FILE#g" \
  "Resources/dev.fulldotdev.appsnap.plist" > "$LAUNCH_AGENT"

/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist" "$LAUNCH_AGENT"
/bin/launchctl bootstrap "$GUI_DOMAIN" "$LAUNCH_AGENT"
/bin/launchctl kickstart -k "$GUI_DOMAIN/$LAUNCH_LABEL"

printf 'Installed Appsnap helper app at %s\n' "$APP_DIR"
printf 'Linked CLI at %s\n' "$BIN_DIR/appsnap"
printf 'Bootstrapped login item at %s\n' "$LAUNCH_AGENT"
printf 'Default global hotkey: Option-Command-S (change it from the Appsnap menu)\n'
printf 'Log: %s\n' "$LOG_FILE"
printf 'No Developer ID signing, notarization, or Apple Developer account is used.\n'
