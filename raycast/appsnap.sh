#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Appsnap
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📸
# @raycast.packageName Appsnap
# @raycast.description Capture context and paste it into the focused text field

set -euo pipefail

if [[ -n "${APPSNAP_BIN:-}" ]]; then
  BIN="$APPSNAP_BIN"
elif [[ -x "/Library/Application Support/Appsnap/appsnap" ]]; then
  BIN="/Library/Application Support/Appsnap/appsnap"
else
  BIN="$HOME/.local/bin/appsnap"
fi

if [[ ! -x "$BIN" ]]; then
  echo "Appsnap executable was not found." >&2
  exit 1
fi

"$BIN"
