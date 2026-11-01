import { execFile } from "child_process";
import { homedir } from "os";
import { resolve, isAbsolute } from "path";
export function run(executable: string, args: string[], cwd?: string): Promise<string> {
  return new Promise((ok, fail) => execFile(executable, args, { cwd, timeout: 20000, maxBuffer: 2 * 1024 * 1024 }, (error, stdout) => {
    if (error) {
      const message=(error as any).code === "ENOENT" ? `${executable} is not installed. Install the CLI and configure access.` : (error as any).killed ? `${executable} timed out. Run long commands in Terminal.` : `${executable} failed. Check configuration and access.`;
      fail(new Error(message)); return;
    }
    ok(String(stdout));
  }));
}
export function configuredRoots(value: string): string[] {
  return value.split("\n").map(s=>s.trim()).filter(Boolean).map(s=> {
    const expanded = s === "~" ? homedir() : s.startsWith("~/") ? resolve(homedir(), s.slice(2)) : s;
    if (!isAbsolute(expanded)) throw new Error("Project roots must be absolute paths");
    return resolve(expanded);
  });
}
export function required(value: string, name: string): string {
  if (!value || /[\0\r\n]/.test(value)) throw new Error(`Configure ${name}`);
  return value;
}
