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

type WindowSelection = {
  target?: { id: number; owner: string; title: string };
  behind?: { id: number; owner: string; title: string };
  error?: string;
};

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

async function selectWindowBehind(bundleId: string): Promise<WindowSelection> {
  const scriptPath = join(environment.assetsPath, "window-behind.js");
  const { stdout } = await execFileAsync("/usr/bin/osascript", [
    "-l",
    "JavaScript",
    scriptPath,
    bundleId,
  ]);

  return JSON.parse(stdout.trim()) as WindowSelection;
}

export default async function command() {
  try {
    const frontmostApplication = await getFrontmostApplication();
    const bundleId = frontmostApplication.bundleId;
    if (!bundleId) {
      await showHUD("Appsnap: the current app has no bundle identifier.");
      return;
    }

    const selection = await selectWindowBehind(bundleId);

    if (selection.error || !selection.behind) {
      await showHUD(
        `Appsnap: ${selection.error ?? "No window found behind this app."}`,
      );
      return;
    }

    const captureDirectory = join(environment.supportPath, "captures");
    await mkdir(captureDirectory, { recursive: true });
    await removeOldCaptures(captureDirectory);

    const capturePath = join(captureDirectory, `appsnap-${Date.now()}.png`);
    await execFileAsync("/usr/sbin/screencapture", [
      "-x",
      "-o",
      "-l",
      String(selection.behind.id),
      capturePath,
    ]);

    await Clipboard.paste({ file: capturePath });
    await showHUD(`Appsnap: pasted ${selection.behind.owner}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    await showHUD(`Appsnap failed: ${message}`);
  }
}
