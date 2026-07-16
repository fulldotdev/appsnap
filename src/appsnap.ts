import {
  Clipboard,
  environment,
  getFrontmostApplication,
  showHUD,
} from "@raycast/api";
import { execFile } from "node:child_process";
import { mkdir, readdir, rm, stat } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const MAX_CAPTURE_AGE_MS = 24 * 60 * 60 * 1000;
const ACTIVATION_DELAY_MS = 400;

type WindowInfo = {
  id: number;
  pid: number;
  owner: string;
  title: string;
};

type FocusInfo = {
  trusted: boolean;
  pid?: number;
  role?: string;
  subrole?: string;
  roleDescription?: string;
  isTextInput: boolean;
};

type WindowContext = {
  focus?: FocusInfo;
  target?: WindowInfo;
  candidates?: WindowInfo[];
  error?: string;
};

type FocusResult = { focus?: FocusInfo; error?: string };
type ActivationResult = { activated?: boolean; error?: string };

async function removeOldCaptures(directory: string) {
  const entries = await readdir(directory).catch(() => []);
  const now = Date.now();

  await Promise.all(
    entries
      .filter((entry) => entry.startsWith("appsnap-") && entry.endsWith(".png"))
      .map(async (entry) => {
        const path = join(directory, entry);
        const metadata = await stat(path).catch(() => undefined);
        if (metadata && now - metadata.mtimeMs > MAX_CAPTURE_AGE_MS) {
          await rm(path, { force: true });
        }
      }),
  );
}

async function runJxa<T>(...arguments_: string[]): Promise<T> {
  const scriptPath = join(environment.assetsPath, "window-behind.js");
  const { stdout } = await execFileAsync("/usr/bin/osascript", [
    "-l",
    "JavaScript",
    scriptPath,
    ...arguments_,
  ]);

  return JSON.parse(stdout.trim()) as T;
}

async function inspectContext(bundleId: string) {
  return runJxa<WindowContext>("inspect", bundleId);
}

async function inspectFocus(pid: number) {
  return runJxa<FocusResult>("focus", String(pid));
}

async function activateWindowOwner(pid: number) {
  return runJxa<ActivationResult>("activate", String(pid));
}

async function captureWindow(window: WindowInfo, capturePath: string) {
  await execFileAsync("/usr/sbin/screencapture", [
    "-x",
    "-o",
    "-l",
    String(window.id),
    capturePath,
  ]);
}

function wait(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export default async function command() {
  try {
    const frontmostApplication = await getFrontmostApplication();
    const bundleId = frontmostApplication.bundleId;
    if (!bundleId) {
      await showHUD("Appsnap: the current app has no bundle identifier.");
      return;
    }

    const context = await inspectContext(bundleId);
    if (context.error || !context.target || !context.focus) {
      await showHUD(
        `Appsnap: ${context.error ?? "Could not inspect the current window."}`,
      );
      return;
    }

    if (!context.focus.trusted) {
      await showHUD("Appsnap needs Accessibility permission for Raycast.");
      return;
    }

    if (context.focus.pid !== context.target.pid) {
      await showHUD("Appsnap could not verify the focused window. Try again.");
      return;
    }

    const candidates = context.candidates ?? [];
    if (candidates.length === 0) {
      await showHUD("Appsnap: no window was found behind the current app.");
      return;
    }

    const captureDirectory = join(environment.supportPath, "captures");
    await mkdir(captureDirectory, { recursive: true });
    await removeOldCaptures(captureDirectory);
    const capturePath = join(captureDirectory, `appsnap-${Date.now()}.png`);

    if (context.focus.isTextInput) {
      const sourceWindow = candidates[0];
      await captureWindow(sourceWindow, capturePath);
      await Clipboard.paste({ file: capturePath });
      await showHUD(`Appsnap: pasted ${sourceWindow.owner}`);
      return;
    }

    await captureWindow(context.target, capturePath);

    for (const candidate of candidates) {
      const activation = await activateWindowOwner(candidate.pid);
      if (!activation.activated) continue;

      await wait(ACTIVATION_DELAY_MS);
      const { focus } = await inspectFocus(candidate.pid);
      if (focus?.trusted && focus.pid === candidate.pid && focus.isTextInput) {
        await Clipboard.paste({ file: capturePath });
        await showHUD(`Appsnap: pasted into ${candidate.owner}`);
        return;
      }
    }

    await Clipboard.copy({ file: capturePath });
    await showHUD("Appsnap: screenshot copied; no focused text field found.");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    await showHUD(`Appsnap failed: ${message}`);
  }
}
