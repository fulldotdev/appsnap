# Appsnap

**Snap any app into your cursor.**

Appsnap is a generic macOS CLI designed to run as a silent Raycast Script Command.

- If a text field is focused, it captures the first useful window behind the focused app and pastes the image back into that field.
- Otherwise, it captures the current window, checks up to three previous apps for a focused text field, and pastes into the first match.
- If no valid target is found, the screenshot remains on the clipboard.
- No app names or target-app lists are hardcoded.

## Requirements

- macOS
- Swift 6 / Xcode Command Line Tools
- Accessibility and Screen Recording permission for the responsible launcher, usually Raycast

## Build

```bash
swift build -c release
```

## Inspect safely

```bash
swift run Appsnap --dry-run --verbose
```

Dry-run needs Accessibility to inspect the focused element but does not capture or paste.

## Install for Raycast

```bash
./scripts/install.sh
```

Or provide your Raycast Script Commands directory:

```bash
./scripts/install.sh "$HOME/path/to/script-commands"
```

Then:

1. Add that Script Commands directory in Raycast settings if needed.
2. Find **Appsnap** in Raycast.
3. Assign a direct global hotkey.
4. Grant Raycast Accessibility and Screen Recording permissions.

The command uses `@raycast.mode silent` to avoid opening a Raycast result window.

## Options

```text
--dry-run
--copy-only
--paste-delay SECONDS
--candidate-delay SECONDS
--max-candidates COUNT
--verbose
```

## Known risk to verify

Raycast may briefly affect application focus even in silent mode. Run `appsnap --dry-run --verbose` from the intended launcher and confirm it reports the app/text field that was focused before invoking the command. If Raycast becomes the detected focus target, a Raycast extension or non-focus-stealing hotkey launcher will be needed.
