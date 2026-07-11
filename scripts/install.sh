#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
RAYCAST_DIR="${1:-$HOME/Documents/Raycast Script Commands}"

mkdir -p "$BIN_DIR" "$RAYCAST_DIR"
cd "$ROOT"
swift build -c release
cp ".build/release/Appsnap" "$BIN_DIR/appsnap"
chmod +x "$BIN_DIR/appsnap"
cp "raycast/appsnap.sh" "$RAYCAST_DIR/Appsnap.sh"
chmod +x "$RAYCAST_DIR/Appsnap.sh"

printf 'Installed binary: %s\n' "$BIN_DIR/appsnap"
printf 'Installed Raycast command: %s\n' "$RAYCAST_DIR/Appsnap.sh"
printf '\nIn Raycast, add this Script Commands directory and assign a hotkey to Appsnap.\n'
