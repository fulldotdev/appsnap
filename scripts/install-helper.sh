#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${APPSNAP_BIN_DIR:-$HOME/.local/bin}"

cd "$ROOT"
swift build -c release
mkdir -p "$BIN_DIR"
install -m 755 ".build/release/appsnap" "$BIN_DIR/appsnap"

printf 'Installed Appsnap helper at %s\n' "$BIN_DIR/appsnap"
printf 'No Developer ID signing, notarization, or Apple Developer account is used.\n'
