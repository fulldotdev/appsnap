#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/installer"
STAGING="$BUILD_DIR/root"
SCRIPTS="$ROOT/installer/scripts"
OUTPUT="$ROOT/dist/Appsnap-Installer.pkg"
APP_SUPPORT="$STAGING/Library/Application Support/Appsnap"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_SUPPORT" "$ROOT/dist"

cd "$ROOT"
swift build -c release
cp ".build/release/Appsnap" "$APP_SUPPORT/appsnap"
cp "raycast/appsnap.sh" "$APP_SUPPORT/Appsnap.sh"
chmod 755 "$APP_SUPPORT/appsnap" "$APP_SUPPORT/Appsnap.sh" "$SCRIPTS/postinstall"

pkgbuild \
  --root "$STAGING" \
  --scripts "$SCRIPTS" \
  --identifier "com.fulldev.appsnap" \
  --version "0.1.0" \
  --install-location "/" \
  "$OUTPUT"

printf 'Built installer: %s\n' "$OUTPUT"
