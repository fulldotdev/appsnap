# Appsnap

**Capture the window behind. Paste it at your cursor.**

Appsnap is a pure Raycast extension for macOS. Assign it a hotkey and invoke it while your cursor is in the field where you want an image attached.

Appsnap then chooses the direction automatically:

- If the current window has a focused text field, it captures the first normal window behind it and pastes the PNG at the current cursor.
- If the current window has no focused text field, it checks only the window directly behind without activating it. If that window remembers a text cursor, Appsnap captures the current window, activates the window behind, confirms the restored focus, and pastes there.
- If the direct-behind window has no remembered text cursor, Appsnap stays in the current window and does nothing.
- If focus restoration fails after activation, Appsnap returns to the original window and copies the screenshot to the clipboard.

There is no window picker, app-name configuration, Swift helper, package installer, or synthetic `Command-V`.

## Requirements

- macOS
- Raycast
- Node.js and pnpm for local development
- Accessibility permission for Raycast, used to inspect focused elements and activate candidate apps
- Screen Recording permission for Raycast, used to capture windows

## Development

```bash
pnpm install
pnpm dev
```

Raycast opens the local extension development workflow. Assign a direct hotkey to **Appsnap** for the intended experience.

## Verify

```bash
pnpm lint
pnpm build
```

## How it works

The TypeScript command uses `getFrontmostApplication()` to remember the current app. A bundled JXA script calls both Accessibility and `CGWindowListCopyWindowInfo` to inspect the focused element and generic macOS window z-order. `/usr/sbin/screencapture` saves the selected source window as a PNG, then Raycast either pastes it with `Clipboard.paste({ file })` or leaves it on the clipboard when no valid text destination is found.

The JXA filter uses window properties only:

- on-screen and not a desktop element;
- layer `0`;
- visible alpha;
- valid window and owner IDs;
- minimum size `120 × 80`.

No app names are hardcoded.

## Distribution

The project is structured as a standard Raycast extension and can be tested locally before submitting it for Raycast Store review.
