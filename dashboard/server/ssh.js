import fs from "node:fs";
import { Client } from "ssh2";
import { WebSocketServer } from "ws";
import { getMachine, hasPrivateKey, PRIVATE_KEY } from "./machines.js";

export function attachSshTerminal(server) {
  const wss = new WebSocketServer({ server, path: "/ws/ssh" });
  // Listen bind errors are handled by the HTTP server starter; avoid crash.
  wss.on("error", () => {});

  wss.on("connection", (ws, req) => {
    const url = new URL(req.url || "", "http://localhost");
    const machineName = url.searchParams.get("machine");
    const machine = getMachine(machineName || "");

    if (!machine) {
      ws.send("\r\n\x1b[31mUnknown machine.\x1b[0m\r\n");
      ws.close();
      return;
    }
    if (!hasPrivateKey()) {
      ws.send(
        "\r\n\x1b[31mMissing keys/id_ed25519. Run make create or generate the key first.\x1b[0m\r\n"
      );
      ws.close();
      return;
    }

    const conn = new Client();
    let stream = null;

    const cleanup = () => {
      try {
        stream?.close();
      } catch {
        /* ignore */
      }
      try {
        conn.end();
      } catch {
        /* ignore */
      }
    };

    ws.on("close", cleanup);
    ws.on("error", cleanup);

    conn.on("ready", () => {
      conn.shell(
        { term: "xterm-256color", cols: 80, rows: 24 },
        (err, sshStream) => {
          if (err) {
            ws.send(`\r\n\x1b[31mShell error: ${err.message}\x1b[0m\r\n`);
            ws.close();
            cleanup();
            return;
          }
          stream = sshStream;
          ws.send(
            `\r\n\x1b[36mConnected to ${machine.name} (${machine.ip}) as devops\x1b[0m\r\n`
          );

          sshStream.on("data", (data) => {
            if (ws.readyState === ws.OPEN) ws.send(data.toString("utf8"));
          });
          sshStream.on("close", () => {
            if (ws.readyState === ws.OPEN) {
              ws.send("\r\n\x1b[33mSession closed.\x1b[0m\r\n");
              ws.close();
            }
            cleanup();
          });
          sshStream.stderr?.on("data", (data) => {
            if (ws.readyState === ws.OPEN) ws.send(data.toString("utf8"));
          });
        }
      );
    });

    conn.on("error", (err) => {
      if (ws.readyState === ws.OPEN) {
        ws.send(`\r\n\x1b[31mSSH error: ${err.message}\x1b[0m\r\n`);
        ws.close();
      }
      cleanup();
    });

    ws.on("message", (raw) => {
      const text = raw.toString();
      try {
        const msg = JSON.parse(text);
        if (msg.type === "resize" && stream) {
          stream.setWindow(msg.rows || 24, msg.cols || 80, 0, 0);
          return;
        }
      } catch {
        /* binary / plain terminal input */
      }
      if (stream) stream.write(text);
    });

    conn.connect({
      host: machine.ip,
      port: 22,
      username: "devops",
      privateKey: fs.readFileSync(PRIVATE_KEY),
      readyTimeout: 12000,
      keepaliveInterval: 10000,
    });
  });

  return wss;
}
