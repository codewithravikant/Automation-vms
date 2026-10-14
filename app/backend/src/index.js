import cors from "cors";
import express from "express";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const MEMINFO_KEYS = {
  MemTotal: null,
  MemAvailable: null,
  MemFree: null,
};

for (const key of Object.keys(MEMINFO_KEYS)) {
  MEMINFO_KEYS[key] = new RegExp(`^${key}:\\s+(\\d+)`, "m");
}

/** Static host facts — refreshed rarely (OS/CPU/NICs almost never change). */
let staticCache = null;
let staticCacheAt = 0;
const STATIC_TTL_MS = 60_000;

function readMemInfo() {
  try {
    const raw = fs.readFileSync("/proc/meminfo", "utf8");
    const get = (key) => {
      const m = raw.match(MEMINFO_KEYS[key]);
      return m ? Number(m[1]) * 1024 : null;
    };
    const total = get("MemTotal");
    const available = get("MemAvailable");
    const free = get("MemFree");
    const used = total != null && available != null ? total - available : null;
    return {
      totalBytes: total,
      availableBytes: available,
      freeBytes: free,
      usedBytes: used,
      usedPercent:
        total && used != null ? Number(((used / total) * 100).toFixed(2)) : null,
    };
  } catch {
    const total = os.totalmem();
    const free = os.freemem();
    const used = total - free;
    return {
      totalBytes: total,
      availableBytes: free,
      freeBytes: free,
      usedBytes: used,
      usedPercent: Number(((used / total) * 100).toFixed(2)),
    };
  }
}

function readLoad() {
  const [one, five, fifteen] = os.loadavg();
  return { "1m": one, "5m": five, "15m": fifteen };
}

function readCpu() {
  const cpus = os.cpus();
  return {
    model: cpus[0]?.model?.trim() || "unknown",
    cores: cpus.length,
    speedMHz: cpus[0]?.speed || null,
  };
}

function detectOs() {
  try {
    const osRelease = fs.readFileSync("/etc/os-release", "utf8");
    const pretty = osRelease.match(/^PRETTY_NAME="?([^"\n]+)"?/m);
    return {
      type: os.type(),
      platform: os.platform(),
      release: os.release(),
      prettyName: pretty?.[1] || `${os.type()} ${os.release()}`,
      arch: os.arch(),
    };
  } catch {
    return {
      type: os.type(),
      platform: os.platform(),
      release: os.release(),
      prettyName: `${os.type()} ${os.release()}`,
      arch: os.arch(),
    };
  }
}

function dockerHint() {
  try {
    const cgroup = fs.readFileSync("/proc/1/cgroup", "utf8");
    const inContainer =
      fs.existsSync("/.dockerenv") || /docker|containerd|kubepods/i.test(cgroup);
    return { runningInContainer: inContainer };
  } catch {
    return {
      runningInContainer: fs.existsSync("/.dockerenv"),
    };
  }
}

function readNetworkInterfaces() {
  return Object.fromEntries(
    Object.entries(os.networkInterfaces()).map(([name, addrs]) => [
      name,
      (addrs || [])
        .filter((a) => a.family === "IPv4" || a.family === 4)
        .map((a) => ({ address: a.address, internal: a.internal })),
    ])
  );
}

function getStaticFacts() {
  const now = Date.now();
  if (!staticCache || now - staticCacheAt > STATIC_TTL_MS) {
    staticCache = {
      os: detectOs(),
      cpu: readCpu(),
      networkInterfaces: readNetworkInterfaces(),
      container: dockerHint(),
      node: {
        version: process.version,
      },
    };
    staticCacheAt = now;
  }
  return staticCache;
}

function liveFields() {
  const hostname = os.hostname();
  return {
    hostname,
    respondingServer: hostname,
    timestamp: new Date().toISOString(),
    uptimeSeconds: Math.floor(os.uptime()),
    memory: readMemInfo(),
    loadAverage: readLoad(),
    node: {
      ...getStaticFacts().node,
      pid: process.pid,
    },
  };
}

function fullMetrics() {
  const staticFacts = getStaticFacts();
  return {
    service: "automation-alchemy-backend",
    ...liveFields(),
    os: staticFacts.os,
    cpu: staticFacts.cpu,
    networkInterfaces: staticFacts.networkInterfaces,
    container: staticFacts.container,
  };
}

/** Build the Express app (exported for tests). */
export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({
      ok: true,
      service: "automation-alchemy-backend",
      hostname: os.hostname(),
    });
  });

  app.get("/metrics", (_req, res) => {
    res.set("Cache-Control", "no-store");
    res.json(fullMetrics());
  });

  /** Volatile fields only — cheap poll target for the UI. */
  app.get("/metrics/live", (_req, res) => {
    res.set("Cache-Control", "no-store");
    res.json({
      service: "automation-alchemy-backend",
      ...liveFields(),
    });
  });

  return app;
}

function isMainModule() {
  const entry = process.argv[1];
  if (!entry) return false;
  try {
    return path.resolve(entry) === fileURLToPath(import.meta.url);
  } catch {
    return false;
  }
}

if (isMainModule()) {
  const PORT = Number(process.env.PORT || 3000);
  createApp().listen(PORT, "0.0.0.0", () => {
    console.log(`Automation-VMs backend on :${PORT}`);
  });
}
