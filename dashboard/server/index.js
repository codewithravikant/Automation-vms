import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import cors from "cors";
import express from "express";
import {
  CPU_OPTIONS,
  getMachine,
  hasPrivateKey,
  loadMachines,
  MEMORY_OPTIONS,
  ROOT,
  updateMachineResources,
} from "./machines.js";
import { attachSshTerminal } from "./ssh.js";
import {
  checkHttp,
  pingHost,
  runVagrantAction,
  runVerify,
  vagrantStatusMap,
} from "./vagrant.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HOST = process.env.HOST || "127.10.10.10";
// Prefer 3030 so we do not collide with Open WebUI / other apps on :3000
const PREFERRED_PORT = Number(process.env.PORT || 3030);
const MAX_PORT_TRIES = 20;
const isProd = process.env.NODE_ENV === "production";

const app = express();
app.use(cors());
app.use(express.json());

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "automation-alchemy-dashboard" });
});

app.get("/api/machines", async (_req, res) => {
  try {
    const machines = loadMachines();
    const { map } = await vagrantStatusMap();
    const enriched = await Promise.all(
      machines.map(async (m) => {
        const state = map[m.name] || "unknown";
        let reachable = false;
        let httpOpen = false;
        if (state === "running") {
          const ping = await pingHost(m.ip);
          reachable = ping.ok;
          if (reachable && m.httpPort) {
            const http = await checkHttp(m.ip, m.httpPort);
            httpOpen = http.ok;
          }
        }
        return {
          ...m,
          state,
          reachable,
          httpOpen,
          publicUrl: m.httpPort ? `http://${m.ip}` : null,
          openPath: m.httpPort ? `/open/${m.name}` : null,
          sshReady: reachable && hasPrivateKey(),
        };
      })
    );
    res.json({
      machines: enriched,
      keyPresent: hasPrivateKey(),
      root: ROOT,
      options: { memory: MEMORY_OPTIONS, cpus: CPU_OPTIONS },
    });
  } catch (err) {
    res.status(500).json({ error: err.message || String(err) });
  }
});

app.patch("/api/machines/:name/resources", async (req, res) => {
  const name = req.params.name;
  const machine = getMachine(name);
  if (!machine) {
    res.status(404).json({ error: "Unknown machine" });
    return;
  }

  const apply = Boolean(req.body?.apply);
  try {
    const updated = updateMachineResources(name, {
      memory: req.body?.memory,
      cpus: req.body?.cpus,
    });

    let reload = null;
    if (apply) {
      // Vagrantfile reads machines.yml → reload applies vb.memory / vb.cpus
      reload = await runVagrantAction("reload", name);
    }

    res.json({
      ok: apply ? Boolean(reload?.ok) : true,
      machine: updated,
      file: "infrastructure/machines.yml",
      applied: apply,
      reload: reload
        ? {
            ok: reload.ok,
            code: reload.code,
            stdout: reload.stdout.slice(-8000),
            stderr: reload.stderr.slice(-4000),
          }
        : null,
      note: apply
        ? "Wrote machines.yml and ran vagrant reload"
        : "Wrote machines.yml — run Apply (reload) or Restart to push into VirtualBox",
    });
  } catch (err) {
    res.status(400).json({ error: err.message || String(err) });
  }
});

app.post("/api/machines/:name/action", async (req, res) => {
  const name = req.params.name;
  const action = String(req.body?.action || "");
  const machine = getMachine(name);
  if (!machine) {
    res.status(404).json({ error: "Unknown machine" });
    return;
  }

  const alias = {
    start: "up",
    stop: "halt",
    restart: "reload",
    destroy: "destroy",
    provision: "provision",
  };
  const vagrantAction = alias[action];
  if (!vagrantAction) {
    res.status(400).json({
      error: "Invalid action. Use start|stop|restart|destroy|provision",
    });
    return;
  }

  try {
    const result = await runVagrantAction(vagrantAction, name);
    res.json({
      ok: result.ok,
      code: result.code,
      stdout: result.stdout.slice(-8000),
      stderr: result.stderr.slice(-4000),
    });
  } catch (err) {
    res.status(500).json({ error: err.message || String(err) });
  }
});

app.post("/api/verify", async (_req, res) => {
  try {
    const result = await runVerify();
    res.json({
      ok: result.ok,
      code: result.code,
      stdout: result.stdout.slice(-12000),
      stderr: result.stderr.slice(-4000),
    });
  } catch (err) {
    res.status(500).json({ error: err.message || String(err) });
  }
});

/** Proxy browser HTTP for VMs that expose it (works through the dashboard tunnel). */
app.use("/open/:name", (req, res) => {
  const machine = getMachine(req.params.name);
  if (!machine?.httpPort) {
    res.status(404).type("text").send("No public HTTP endpoint on this machine");
    return;
  }

  const suffix = req.url === "/" ? "/" : req.url;
  const upstream = http.request(
    {
      host: machine.ip,
      port: machine.httpPort,
      path: suffix,
      method: req.method,
      headers: {
        ...req.headers,
        host: `${machine.ip}:${machine.httpPort}`,
      },
      timeout: 5000,
      family: 4,
    },
    (upRes) => {
      res.writeHead(upRes.statusCode || 502, upRes.headers);
      upRes.pipe(res);
    }
  );
  upstream.on("timeout", () => {
    upstream.destroy();
    if (!res.headersSent) {
      res.status(504).type("text").send("Timed out reaching public HTTP");
    }
  });
  upstream.on("error", (err) => {
    if (!res.headersSent) {
      res
        .status(502)
        .type("text")
        .send(
          `Public HTTP not reachable on ${machine.ip}:${machine.httpPort} (${err.message}). Provision the loadbalancer if nginx is missing.`
        );
    }
  });
  req.pipe(upstream);
});

if (isProd) {
  const dist = path.join(__dirname, "../dist");
  app.use(express.static(dist));
  app.get("*", (_req, res) => {
    res.sendFile(path.join(dist, "index.html"));
  });
}

const server = http.createServer(app);
attachSshTerminal(server);

function listenOnPort(port) {
  return new Promise((resolve, reject) => {
    const onError = (err) => {
      server.off("listening", onListening);
      reject(err);
    };
    const onListening = () => {
      server.off("error", onError);
      resolve(port);
    };
    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(port, HOST);
  });
}

async function start() {
  let port = PREFERRED_PORT;
  for (let i = 0; i < MAX_PORT_TRIES; i += 1) {
    try {
      await listenOnPort(port);
      console.log("Automation-VMs dashboard ready");
      console.log(`  → http://${HOST}:${port}`);
      console.log(`Mode: ${isProd ? "production" : "development"}`);
      return;
    } catch (err) {
      if (err?.code === "EADDRNOTAVAIL") {
        throw new Error(
          `Address ${HOST} is not available. Run: ./scripts/ensure-dashboard-host.sh`
        );
      }
      if (err?.code !== "EADDRINUSE") {
        throw err;
      }
      const next = port + 1;
      console.log(`Port ${port} busy on ${HOST} — trying ${next}…`);
      port = next;
    }
  }
  throw new Error(
    `No free port found on ${HOST} from ${PREFERRED_PORT} to ${PREFERRED_PORT + MAX_PORT_TRIES - 1}`
  );
}

start().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
