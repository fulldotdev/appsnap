import { showHUD } from "@raycast/api";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile, unlink } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

function lastLine(value: string) {
  const lines = value.trim().split("\n");
  return lines[lines.length - 1];
}

export default async function command() {
  const appPath =
    process.env.APPSNAP_APP ??
    join(homedir(), ".local", "Applications", "Appsnap.app");
  const resultPath = join(tmpdir(), `appsnap-result-${randomUUID()}.txt`);
  console.log("Appsnap launcher invoked", appPath);

  try {
    await unlink(resultPath).catch(() => undefined);
    await execFileAsync(
      "/usr/bin/open",
      ["-W", "-n", appPath, "--args", "--result-file", resultPath],
      { timeout: 15_000, killSignal: "SIGKILL" },
    );
    const result = await readFile(resultPath, "utf8");
    console.log("Appsnap helper completed", result.trim());
    await showHUD(lastLine(result) || "Appsnap complete.");
  } catch (error) {
    const failure = error as Error & { stderr?: string };
    console.error("Appsnap helper failed", failure);
    const result = await readFile(resultPath, "utf8").catch(() => "");
    const message =
      lastLine(result) ||
      (failure.stderr ? lastLine(failure.stderr) : undefined) ||
      failure.message;
    await showHUD(message);
  } finally {
    await unlink(resultPath).catch(() => undefined);
  }
}
