import { useCallback, useEffect, useState } from "react";
import Topology from "./components/Topology.jsx";
import TerminalPanel from "./components/TerminalPanel.jsx";
import VmCard from "./components/VmCard.jsx";
import OnboardingOverlay, {
  shouldShowOnboarding,
} from "./components/OnboardingOverlay.jsx";
import { useTheme } from "./theme.jsx";

async function api(path, opts) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...opts,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}

export default function App() {
  const { theme, toggle } = useTheme();
  const [machines, setMachines] = useState([]);
  const [resourceOptions, setResourceOptions] = useState(null);
  const [keyPresent, setKeyPresent] = useState(false);
  const [selected, setSelected] = useState(null);
  const [termSession, setTermSession] = useState(0);
  const [busy, setBusy] = useState(null);
  const [log, setLog] = useState("");
  const [flash, setFlash] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showOnboarding, setShowOnboarding] = useState(shouldShowOnboarding);

  const refresh = useCallback(async () => {
    try {
      const data = await api("/api/machines");
      setMachines(data.machines || []);
      setResourceOptions(data.options || null);
      setKeyPresent(!!data.keyPresent);
      setSelected((prev) => {
        if (prev && data.machines?.some((m) => m.name === prev)) return prev;
        return data.machines?.[0]?.name || null;
      });
    } catch (err) {
      setFlash({ type: "err", text: err.message });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 8000);
    return () => clearInterval(id);
  }, [refresh]);

  useEffect(() => {
    if (!flash) return;
    const t = setTimeout(() => setFlash(null), 4200);
    return () => clearTimeout(t);
  }, [flash]);

  const runAction = async (name, action) => {
    const key = `${name}:${action}`;
    setBusy(key);
    setLog(`Running ${action} on ${name}…\n`);
    try {
      const result = await api(`/api/machines/${name}/action`, {
        method: "POST",
        body: JSON.stringify({ action }),
      });
      const out = [result.stdout, result.stderr].filter(Boolean).join("\n");
      setLog(out || `(exit ${result.code})`);
      setFlash({
        type: result.ok ? "ok" : "err",
        text: result.ok
          ? `${action} completed on ${name}`
          : `${action} failed on ${name}`,
      });
      await refresh();
    } catch (err) {
      setFlash({ type: "err", text: err.message });
      setLog(err.message);
    } finally {
      setBusy(null);
    }
  };

  const saveResources = async (name, { memory, cpus, apply }) => {
    setBusy(`${name}:resources`);
    setLog(
      apply
        ? `Saving CPU/RAM for ${name} to machines.yml and applying (vagrant reload)…\n`
        : `Saving CPU/RAM for ${name} to infrastructure/machines.yml…\n`
    );
    try {
      const result = await api(`/api/machines/${name}/resources`, {
        method: "PATCH",
        body: JSON.stringify({ memory, cpus, apply }),
      });
      const reloadOut = result.reload
        ? [result.reload.stdout, result.reload.stderr].filter(Boolean).join("\n")
        : "";
      setLog(
        [
          `Updated ${result.file}`,
          `memory=${result.machine.memory} MB  cpus=${result.machine.cpus}`,
          result.note,
          reloadOut,
        ]
          .filter(Boolean)
          .join("\n")
      );
      setFlash({
        type: result.ok ? "ok" : "err",
        text: result.ok
          ? apply
            ? `Applied ${name}: ${result.machine.memory} MB / ${result.machine.cpus} CPU`
            : `Saved ${name} → machines.yml`
          : `Failed to apply resources on ${name}`,
      });
      await refresh();
    } catch (err) {
      setFlash({ type: "err", text: err.message });
      setLog(err.message);
    } finally {
      setBusy(null);
    }
  };

  const saveResourcesBatch = async (updates) => {
    const lines = [];
    for (const { name, memory, cpus } of updates) {
      const result = await api(`/api/machines/${name}/resources`, {
        method: "PATCH",
        body: JSON.stringify({ memory, cpus, apply: false }),
      });
      lines.push(
        `${name}: memory=${result.machine.memory} MB  cpus=${result.machine.cpus}`
      );
    }
    await refresh();
    return lines;
  };

  const runVerify = async () => {
    setBusy("verify");
    setLog("Running make verify…\n");
    try {
      const result = await api("/api/verify", { method: "POST", body: "{}" });
      setLog([result.stdout, result.stderr].filter(Boolean).join("\n"));
      setFlash({
        type: result.ok ? "ok" : "err",
        text: result.ok ? "Validation PASSED" : "Validation FAILED",
      });
    } catch (err) {
      setFlash({ type: "err", text: err.message });
    } finally {
      setBusy(null);
    }
  };

  const openTerminal = (name) => {
    setSelected(name);
    setTermSession((n) => n + 1);
    setFlash({ type: "ok", text: `Opening terminal → ${name}` });
    requestAnimationFrame(() => {
      document.getElementById("ssh-terminal")?.scrollIntoView({
        behavior: "smooth",
        block: "nearest",
      });
    });
  };

  const selectedMachine = machines.find((m) => m.name === selected) || null;

  const handleOnboardingComplete = ({ skipped, saved }) => {
    setShowOnboarding(false);
    if (saved) {
      setFlash({ type: "ok", text: "Lab resources saved to machines.yml" });
      setLog("Onboarding saved RAM/CPU to infrastructure/machines.yml");
    } else if (skipped) {
      setFlash({ type: "ok", text: "Setup skipped — you can edit RAM/CPU on each VM card" });
    }
  };

  const handleOnboardingSave = async (updates) => {
    const lines = await saveResourcesBatch(updates);
    setLog(["Onboarding resource save:", ...lines].join("\n"));
  };

  return (
    <div className="app">
      {showOnboarding && !loading && (
        <OnboardingOverlay
          machines={machines}
          options={resourceOptions}
          keyPresent={keyPresent}
          onComplete={handleOnboardingComplete}
          onSaveAll={handleOnboardingSave}
        />
      )}

      <header className="topbar">
        <div className="brand">
          <h1>
            Infrastructure <span>Insight</span>
          </h1>
          <p>Lab control plane — VMs, status, and live SSH</p>
        </div>
        <div className="top-actions">
          <button className="btn btn-ghost" type="button" onClick={toggle}>
            {theme === "dark" ? "Light mode" : "Dark mode"}
          </button>
          <button
            className="btn"
            type="button"
            onClick={refresh}
            disabled={busy !== null}
          >
            Refresh
          </button>
          <button
            className="btn btn-accent"
            type="button"
            onClick={runVerify}
            disabled={busy !== null}
          >
            {busy === "verify" ? "Validating…" : "Run validation"}
          </button>
        </div>
      </header>

      {!keyPresent && (
        <div className="panel" style={{ animationDelay: "0.05s" }}>
          SSH key missing at <code>keys/id_ed25519</code>. Generate it with{" "}
          <code>make create</code> before opening terminals.
        </div>
      )}

      <div className="layout">
        <section className="panel">
          <h2>Virtual machines</h2>
          {loading ? (
            <p style={{ color: "var(--muted)" }}>Loading status…</p>
          ) : (
            <div className="vm-grid">
              {machines.map((m) => (
                <VmCard
                  key={m.name}
                  machine={m}
                  active={selected === m.name}
                  busy={busy}
                  options={resourceOptions}
                  onSelect={() => setSelected(m.name)}
                  onAction={runAction}
                  onSaveResources={saveResources}
                  onOpenTerminal={openTerminal}
                />
              ))}
            </div>
          )}
          {log && <div className="log-box">{log}</div>}
        </section>

        <section className="panel topology">
          <h2>Network topology</h2>
          <Topology
            machines={machines}
            selected={selected}
            onSelect={setSelected}
          />
        </section>
      </div>

      <section className="panel terminal-shell">
        <div className="term-bar">
          <h2 style={{ margin: 0 }}>
            Terminal
            {selectedMachine ? ` · ${selectedMachine.name}` : ""}
          </h2>
          <div className="term-switch">
            {machines.map((m) => (
              <button
                key={m.name}
                type="button"
                className={`btn${selected === m.name ? " btn-accent" : ""}`}
                onClick={() => openTerminal(m.name)}
              >
                {m.name}
              </button>
            ))}
          </div>
          <code>
            {selectedMachine
              ? `ssh -i keys/id_ed25519 devops@${selectedMachine.ip}`
              : "Select a VM"}
          </code>
        </div>
        <TerminalPanel machine={selectedMachine} sessionKey={termSession} />
      </section>

      {flash && (
        <div className={`flash ${flash.type === "ok" ? "ok" : "err"}`}>
          {flash.text}
        </div>
      )}
    </div>
  );
}
