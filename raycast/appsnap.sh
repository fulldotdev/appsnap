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

BIN="${APPSNAP_BIN:-$HOME/.local/bin/appsnap}"

if [[ ! -x "$BIN" ]]; then
  echo "Appsnap is not installed at $BIN" >&2
  exit 1
fi

"$BIN"
