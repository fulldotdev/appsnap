# Appsnap

**Capture the window behind. Paste it at your cursor.**

Appsnap is a pure Raycast extension for macOS. Assign it a hotkey and invoke it while your cursor is in the field where you want an image attached.

Appsnap then:

1. remembers the app that was frontmost when invoked;
2. finds that app's frontmost normal window in macOS window order;
3. captures the first normal window directly behind it;
4. pastes the resulting PNG at the original cursor using Raycast's clipboard API.

There is no window picker, app-name configuration, Swift helper, package installer, or synthetic `Command-V`.

## Requirements

- macOS
- Raycast
- Node.js and pnpm for local development
- Screen Recording permission for Raycast

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

The TypeScript command uses `getFrontmostApplication()` to remember the paste target. A bundled JXA script calls `CGWindowListCopyWindowInfo` to inspect generic macOS window z-order and returns the first normal window behind the target. `/usr/sbin/screencapture` saves that window as a PNG, then `Clipboard.paste({ file })` pastes it through Raycast.

The JXA filter uses window properties only:

- on-screen and not a desktop element;
- layer `0`;
- visible alpha;
- valid window and owner IDs;
- minimum size `120 × 80`.

No app names are hardcoded.

## Deliberate simplification

Appsnap assumes you invoke it while the destination cursor is already active. It does not inspect Accessibility text-field roles. If the destination does not accept image/file paste, the receiving app decides what happens.

## Distribution

The project is structured as a standard Raycast extension and can be tested locally before submitting it for Raycast Store review.
