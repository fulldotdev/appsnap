# Appsnap

**Snap any app into your cursor.**

Appsnap is a native local macOS helper launched by a thin Raycast extension.

- If the current window has a verified text cursor, Appsnap captures the normal window directly behind it and pastes the image at the current cursor.
- Otherwise, Appsnap captures the current window, activates only the directly-behind window, and pastes only when that exact window and a text cursor are verified.
- If verification fails, Appsnap restores the original window and leaves the screenshot on the clipboard.
- It never searches a second or third background candidate.

There is no window picker, app-name configuration, Apple Developer account, Developer ID signing, notarization, installer package, or synthetic app-specific behavior.

## How it is installed

The repository contains:

- a native Swift helper at `Sources/Appsnap/Appsnap.swift`;
- a standard Raycast no-view command that launches the locally installed `Appsnap.app` helper;
- `scripts/install-helper.sh`, which builds the helper locally and installs it under `~/.local/Applications`.

Install or update the helper:

```bash
./scripts/install-helper.sh
```

The binary is built on this Mac with Swift Package Manager. Because it is built locally and never distributed as a downloaded executable, no Apple account, certificate, Developer ID signing, or notarization is required. Swift may add a local ad-hoc linker signature; that does not use or contact an Apple account.

## Raycast shortcut

Run `pnpm dev`, find **Appsnap** in Raycast, and assign it a direct global hotkey. The Raycast command is intentionally thin: it only launches the native helper and shows its result.

## Permissions

Grant the locally built **Appsnap** helper:

- Accessibility, for exact focus/window verification and Command-V;
- Screen & System Audio Recording, for window capture.

The first run requests these permissions through macOS System Settings. No System Events Automation permission is needed.

## Development

```bash
pnpm install
./scripts/install-helper.sh
pnpm dev
```

## Verification

```bash
swift build -c release
~/.local/bin/appsnap --dry-run --verbose
pnpm lint
pnpm build
```

## CLI options

```text
--dry-run
--copy-only
--activation-delay SECONDS
--paste-delay SECONDS
--verbose
```

The helper uses CoreGraphics for front-to-back window order and direct window capture, and the native Accessibility API for cursor inspection and exact-window raising. Paste is dispatched only after the destination window and text cursor have both been verified.
