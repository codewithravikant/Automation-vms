import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";

function wsUrl(machineName) {
  const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
  const host = window.location.host;
  return `${proto}//${host}/ws/ssh?machine=${encodeURIComponent(machineName)}`;
}

export default function TerminalPanel({ machine, sessionKey }) {
  const hostRef = useRef(null);
  const termRef = useRef(null);
  const fitRef = useRef(null);
  const socketRef = useRef(null);

  useEffect(() => {
    if (!hostRef.current) return;

    const term = new Terminal({
      cursorBlink: true,
      fontFamily: '"JetBrains Mono", monospace',
      fontSize: 13,
      theme: {
        background: "#070d18",
        foreground: "#d7e2f5",
        cursor: "#2ec4b6",
        selectionBackground: "rgba(46,196,182,0.35)",
      },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(hostRef.current);
    fit.fit();
    termRef.current = term;
    fitRef.current = fit;

    const onResize = () => {
      fit.fit();
      const sock = socketRef.current;
      if (sock?.readyState === WebSocket.OPEN) {
        sock.send(
          JSON.stringify({
            type: "resize",
            cols: term.cols,
            rows: term.rows,
          })
        );
      }
    };
    window.addEventListener("resize", onResize);

    return () => {
      window.removeEventListener("resize", onResize);
      socketRef.current?.close();
      socketRef.current = null;
      term.dispose();
      termRef.current = null;
      fitRef.current = null;
    };
  }, []);

  useEffect(() => {
    const term = termRef.current;
    if (!term) return;

    socketRef.current?.close();
    socketRef.current = null;
    term.reset();

    if (!machine) {
      term.writeln("\x1b[90mSelect a VM to open an SSH session as devops.\x1b[0m");
      return;
    }

    term.writeln(
      `\x1b[36mConnecting to ${machine.name} (${machine.ip})…\x1b[0m`
    );

    const sock = new WebSocket(wsUrl(machine.name));
    socketRef.current = sock;

    sock.onopen = () => {
      fitRef.current?.fit();
      sock.send(
        JSON.stringify({
          type: "resize",
          cols: term.cols,
          rows: term.rows,
        })
      );
    };

    sock.onmessage = (ev) => {
      term.write(typeof ev.data === "string" ? ev.data : "");
    };

    sock.onerror = () => {
      term.writeln("\r\n\x1b[31mWebSocket error.\x1b[0m");
    };

    sock.onclose = () => {
      term.writeln("\r\n\x1b[33mDisconnected.\x1b[0m");
    };

    const disposable = term.onData((data) => {
      if (sock.readyState === WebSocket.OPEN) sock.send(data);
    });

    return () => {
      disposable.dispose();
      sock.close();
      if (socketRef.current === sock) socketRef.current = null;
    };
  }, [machine?.name, machine?.ip, sessionKey]);

  return <div className="xterm-wrap" ref={hostRef} id="ssh-terminal" />;
}
