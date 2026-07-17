import { showHUD } from "@raycast/api";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

function lastLine(value: string) {
  const lines = value.trim().split("\n");
  return lines[lines.length - 1];
}

export default async function command() {
  const helperPath =
    process.env.APPSNAP_BIN ?? join(homedir(), ".local", "bin", "appsnap");

  try {
    const { stdout } = await execFileAsync(helperPath, [], {
      timeout: 12_000,
      killSignal: "SIGKILL",
    });
    const message = lastLine(stdout);
    await showHUD(message || "Appsnap complete.");
  } catch (error) {
    const failure = error as Error & { stderr?: string };
    const message =
      (failure.stderr ? lastLine(failure.stderr) : undefined) ||
      failure.message;
    await showHUD(message);
  }
}
