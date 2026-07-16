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
const ACTIVATION_DELAY_MS = 1200;

type WindowInfo = {
  id: number;
  pid: number;
  owner: string;
  title: string;
  x: number;
  y: number;
  width: number;
  height: number;
};

type FocusInfo = {
  trusted: boolean;
  pid?: number;
  role?: string;
  subrole?: string;
  roleDescription?: string;
  isTextInput: boolean;
  activeWindowVerified?: boolean;
};

type WindowContext = {
  focus?: FocusInfo;
  target?: WindowInfo;
  behind?: WindowInfo | null;
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

async function runJxa<T>(timeout: number, ...arguments_: string[]): Promise<T> {
  const scriptPath = join(environment.assetsPath, "window-behind.js");
  const { stdout } = await execFileAsync(
    "/usr/bin/osascript",
    ["-l", "JavaScript", scriptPath, ...arguments_],
    { timeout, killSignal: "SIGKILL" },
  );

  return JSON.parse(stdout.trim()) as T;
}

async function inspectContext(bundleId: string) {
  return runJxa<WindowContext>(3000, "inspect", bundleId);
}

function windowArguments(window: WindowInfo) {
  return [
    String(window.pid),
    String(window.id),
    window.title,
    String(window.x),
    String(window.y),
    String(window.width),
    String(window.height),
  ];
}

async function inspectFocus(window: WindowInfo) {
  return runJxa<FocusResult>(2200, "focus-active", ...windowArguments(window));
}

async function activateWindow(window: WindowInfo) {
  return runJxa<ActivationResult>(1800, "activate", ...windowArguments(window));
}

async function captureWindow(window: WindowInfo, capturePath: string) {
  const arguments_ = ["-x", "-o", "-l", String(window.id), capturePath];
  try {
    await execFileAsync("/usr/sbin/screencapture", arguments_, {
      timeout: 2000,
      killSignal: "SIGKILL",
    });
  } catch {
    await rm(capturePath, { force: true });
    await wait(150);
    await execFileAsync("/usr/sbin/screencapture", arguments_, {
      timeout: 2000,
      killSignal: "SIGKILL",
    });
  }
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
      await showHUD(
        "Appsnap needs Accessibility and Automation permissions for Raycast.",
      );
      return;
    }

    const behind = context.behind;
    if (!behind) {
      await showHUD("Appsnap: no window was found directly behind this app.");
      return;
    }

    const captureDirectory = join(environment.supportPath, "captures");
    await mkdir(captureDirectory, { recursive: true });
    await removeOldCaptures(captureDirectory);
    const capturePath = join(captureDirectory, `appsnap-${Date.now()}.png`);

    if (context.focus.isTextInput) {
      await captureWindow(behind, capturePath);
      await Clipboard.paste({ file: capturePath });
      await showHUD(`Appsnap: pasted ${behind.owner}`);
      return;
    }

    await captureWindow(context.target, capturePath);
    const activation = await activateWindow(behind);

    if (activation.activated) {
      await wait(ACTIVATION_DELAY_MS);
      const { focus } = await inspectFocus(behind);

      if (
        focus?.trusted &&
        focus.activeWindowVerified &&
        focus.pid === behind.pid &&
        focus.isTextInput
      ) {
        await Clipboard.paste({ file: capturePath });

        await showHUD(`Appsnap: pasted into ${behind.owner}`);
        return;
      }
    }

    await Clipboard.copy({ file: capturePath });
    const restoration = await activateWindow(context.target);
    if (restoration.activated) {
      await showHUD(
        "Appsnap: returned to the original window; screenshot copied.",
      );
    } else {
      await showHUD(
        "Appsnap: screenshot copied, but the original window could not be restored.",
      );
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";

    await showHUD(`Appsnap failed: ${message}`);
  }
}
