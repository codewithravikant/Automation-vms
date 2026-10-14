import http from "node:http";
import { spawn } from "node:child_process";
import path from "node:path";
import { INFRA_DIR, ROOT } from "./machines.js";

const ALLOWED = new Set([
  "up",
  "halt",
  "reload",
  "destroy",
  "status",
  "provision",
]);

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, {
      cwd: INFRA_DIR,
      env: process.env,
      ...opts,
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d) => {
      stdout += d.toString();
    });
    child.stderr?.on("data", (d) => {
      stderr += d.toString();
    });
    child.on("error", (err) => {
      resolve({ ok: false, code: 1, stdout, stderr: err.message });
    });
    child.on("close", (code) => {
      resolve({ ok: code === 0, code: code ?? 1, stdout, stderr });
    });
  });
}

/** Map vagrant status machine-readable lines to name -> state */
export async function vagrantStatusMap() {
  const result = await run("vagrant", ["status", "--machine-readable"]);
  const map = {};
  for (const line of result.stdout.split("\n")) {
    // timestamp,target,type,data...
    const parts = line.split(",");
    if (parts.length < 4) continue;
    const [, target, type, ...dataParts] = parts;
    if (type === "state" && target) {
      map[target] = dataParts.join(",");
    }
  }
  return { map, raw: result };
}

export async function runVagrantAction(action, machine) {
  if (!ALLOWED.has(action)) {
    return { ok: false, code: 1, stdout: "", stderr: `Disallowed action: ${action}` };
  }
  if (!machine || !/^[a-zA-Z0-9_-]+$/.test(machine)) {
    return { ok: false, code: 1, stdout: "", stderr: "Invalid machine name" };
  }

  const args = [action, machine];
  if (action === "destroy") {
    args.splice(1, 0, "-f");
  }
  if (action === "up") {
    // provision on first create is fine; keep default
  }

  return run("vagrant", args);
}

export async function runVerify() {
  return run("bash", [path.join(ROOT, "scripts/verify.sh")], { cwd: ROOT });
}

export async function pingHost(ip) {
  const isDarwin = process.platform === "darwin";
  const args = isDarwin
    ? ["-c", "1", "-W", "1000", ip]
    : ["-c", "1", "-W", "1", ip];
  return run("ping", args);
}

/** True when something answers HTTP on ip:port (any status code). */
export function checkHttp(ip, port, timeoutMs = 1500) {
  return new Promise((resolve) => {
    const req = http.get(
      { host: ip, port, path: "/", timeout: timeoutMs, family: 4 },
      (res) => {
        res.resume();
        resolve({ ok: true, statusCode: res.statusCode });
      }
    );
    req.on("timeout", () => {
      req.destroy();
      resolve({ ok: false });
    });
    req.on("error", () => resolve({ ok: false }));
  });
}
