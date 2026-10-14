import { useEffect, useMemo, useState } from "react";

const STORAGE_KEY = "ss-onboarding-done";
const MIN_MEMORY = 512;
const MIN_CPUS = 1;
const HOST_FREE_RAM_GB = 2;

const DEFAULT_MEMORY = [256, 512, 768, 1024, 1536, 2048, 3072, 4096];
const DEFAULT_CPUS = [1, 2, 3, 4];

const GUIDES = [
  {
    title: "Free host RAM",
    body: "Aim for at least ~2 GB free before creating all five VMs. On macOS: Activity Monitor → Memory. On Linux: free -h. On Windows: Task Manager → Performance.",
  },
  {
    title: "VirtualBox + Vagrant",
    body: "Install VirtualBox, then Vagrant. Confirm with vagrant --version in a terminal. The lab will not boot without both.",
  },
  {
    title: "SSH key",
    body: "Run make create from the project root. That generates keys/id_ed25519 and brings the VMs up. Terminals in this dashboard need that key.",
  },
  {
    title: "Where settings land",
    body: "RAM and CPU here write to infrastructure/machines.yml. Use Save & apply later on each card (or after create) so VirtualBox picks them up.",
  },
];

export function shouldShowOnboarding() {
  try {
    return localStorage.getItem(STORAGE_KEY) !== "1";
  } catch {
    return true;
  }
}

export function markOnboardingDone() {
  try {
    localStorage.setItem(STORAGE_KEY, "1");
  } catch {
    /* ignore quota / private mode */
  }
}

function buildDraft(machines) {
  const draft = {};
  for (const m of machines) {
    draft[m.name] = {
      memory: Math.max(Number(m.memory) || MIN_MEMORY, MIN_MEMORY),
      cpus: Math.max(Number(m.cpus) || MIN_CPUS, MIN_CPUS),
    };
  }
  return draft;
}

export default function OnboardingOverlay({
  machines,
  options,
  keyPresent,
  onComplete,
  onSaveAll,
}) {
  const memoryOpts = options?.memory || DEFAULT_MEMORY;
  const cpuOpts = options?.cpus || DEFAULT_CPUS;
  const [draft, setDraft] = useState(() => buildDraft(machines));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [applyAll, setApplyAll] = useState({
    memory: MIN_MEMORY,
    cpus: MIN_CPUS,
  });

  useEffect(() => {
    setDraft(buildDraft(machines));
  }, [machines]);

  const totalMb = useMemo(
    () => Object.values(draft).reduce((sum, row) => sum + (row.memory || 0), 0),
    [draft]
  );
  const totalCpus = useMemo(
    () => Object.values(draft).reduce((sum, row) => sum + (row.cpus || 0), 0),
    [draft]
  );

  const underMin = useMemo(
    () =>
      Object.entries(draft).filter(
        ([, row]) => row.memory < MIN_MEMORY || row.cpus < MIN_CPUS
      ),
    [draft]
  );

  const finish = (saved) => {
    markOnboardingDone();
    onComplete({ skipped: !saved, saved });
  };

  const updateMachine = (name, patch) => {
    setDraft((prev) => ({
      ...prev,
      [name]: { ...prev[name], ...patch },
    }));
  };

  const applyToAll = () => {
    const memory = Number(applyAll.memory);
    const cpus = Number(applyAll.cpus);
    setDraft((prev) => {
      const next = { ...prev };
      for (const name of Object.keys(next)) {
        next[name] = { memory, cpus };
      }
      return next;
    });
  };

  const handleSkip = () => finish(false);

  const handleContinue = async () => {
    if (underMin.length) {
      setError(
        `Each VM needs at least ${MIN_MEMORY} MB RAM and ${MIN_CPUS} CPU.`
      );
      return;
    }
    if (!machines.length) {
      finish(false);
      return;
    }

    const updates = machines
      .map((m) => {
        const row = draft[m.name];
        if (!row) return null;
        if (row.memory === m.memory && row.cpus === m.cpus) return null;
        return { name: m.name, memory: row.memory, cpus: row.cpus };
      })
      .filter(Boolean);

    setBusy(true);
    setError(null);
    try {
      if (updates.length && onSaveAll) {
        await onSaveAll(updates);
      }
      finish(true);
    } catch (err) {
      setError(err.message || "Could not save resources");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="onboard-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboard-title">
      <div className="onboard-modal">
        <header className="onboard-head">
          <div>
            <p className="onboard-eyebrow">Before you start</p>
            <h2 id="onboard-title">
              Lab setup <span>checklist</span>
            </h2>
            <p className="onboard-lead">
              Confirm host capacity and set RAM/CPU for each VM. You can skip and
              change these later on the dashboard cards.
            </p>
          </div>
          <button
            className="btn btn-ghost"
            type="button"
            onClick={handleSkip}
            disabled={busy}
          >
            Skip
          </button>
        </header>

        <div className="onboard-warn" role="status">
          <strong>Minimum resources</strong>
          <p>
            Each VM needs at least <b>{MIN_MEMORY} MB RAM</b> and{" "}
            <b>{MIN_CPUS} CPU</b>. Plan on roughly{" "}
            <b>~{HOST_FREE_RAM_GB} GB free host RAM</b> for the full four-VM lab
            at defaults (about {HOST_FREE_RAM_GB}+ GB total guest memory). Going
            below the minimum risks slow boots or failed creates.
          </p>
        </div>

        <div className="onboard-grid">
          <section className="onboard-section">
            <h3>What you need</h3>
            <ul className="onboard-checklist">
              <li>
                <span className="onboard-dot ok" />
                Host free RAM ≥ ~{HOST_FREE_RAM_GB} GB
              </li>
              <li>
                <span className="onboard-dot ok" />
                VirtualBox + Vagrant installed
              </li>
              <li>
                <span className={`onboard-dot ${keyPresent ? "ok" : "warn"}`} />
                SSH key at <code>keys/id_ed25519</code>
                {keyPresent ? " (found)" : " — run make create"}
              </li>
              <li>
                <span className="onboard-dot ok" />
                Per-VM floor: {MIN_MEMORY} MB / {MIN_CPUS} CPU
              </li>
            </ul>

            <h3>Where to find this info</h3>
            <div className="onboard-guides">
              {GUIDES.map((g) => (
                <details key={g.title} className="onboard-guide">
                  <summary>{g.title}</summary>
                  <p>{g.body}</p>
                </details>
              ))}
            </div>
          </section>

          <section className="onboard-section">
            <h3>VM resources</h3>
            <p className="onboard-hint">
              Defaults match <code>infrastructure/machines.yml</code>. Values
              below {MIN_MEMORY} MB or {MIN_CPUS} CPU are blocked.
            </p>

            <div className="onboard-apply-all">
              <label className="resource-field">
                <span>Apply RAM</span>
                <select
                  value={applyAll.memory}
                  disabled={busy}
                  onChange={(e) =>
                    setApplyAll((p) => ({
                      ...p,
                      memory: Number(e.target.value),
                    }))
                  }
                >
                  {memoryOpts
                    .filter((mb) => mb >= MIN_MEMORY)
                    .map((mb) => (
                      <option key={mb} value={mb}>
                        {mb} MB
                      </option>
                    ))}
                </select>
              </label>
              <label className="resource-field">
                <span>Apply CPU</span>
                <select
                  value={applyAll.cpus}
                  disabled={busy}
                  onChange={(e) =>
                    setApplyAll((p) => ({
                      ...p,
                      cpus: Number(e.target.value),
                    }))
                  }
                >
                  {cpuOpts
                    .filter((n) => n >= MIN_CPUS)
                    .map((n) => (
                      <option key={n} value={n}>
                        {n}
                      </option>
                    ))}
                </select>
              </label>
              <button
                className="btn"
                type="button"
                disabled={busy || !machines.length}
                onClick={applyToAll}
              >
                Apply to all
              </button>
            </div>

            <div className="onboard-machines">
              {machines.length === 0 ? (
                <p className="onboard-hint">Loading machine list…</p>
              ) : (
                machines.map((m) => {
                  const row = draft[m.name] || {
                    memory: MIN_MEMORY,
                    cpus: MIN_CPUS,
                  };
                  const bad =
                    row.memory < MIN_MEMORY || row.cpus < MIN_CPUS;
                  return (
                    <div
                      key={m.name}
                      className={`onboard-machine${bad ? " bad" : ""}`}
                    >
                      <div className="onboard-machine-meta">
                        <strong>{m.name}</strong>
                        <span>
                          {m.ip} · {m.role}
                        </span>
                      </div>
                      <label className="resource-field">
                        <span>RAM</span>
                        <select
                          value={row.memory}
                          disabled={busy}
                          onChange={(e) =>
                            updateMachine(m.name, {
                              memory: Number(e.target.value),
                            })
                          }
                        >
                          {memoryOpts.map((mb) => (
                            <option key={mb} value={mb}>
                              {mb} MB
                              {mb < MIN_MEMORY ? " (below min)" : ""}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="resource-field">
                        <span>CPU</span>
                        <select
                          value={row.cpus}
                          disabled={busy}
                          onChange={(e) =>
                            updateMachine(m.name, {
                              cpus: Number(e.target.value),
                            })
                          }
                        >
                          {cpuOpts.map((n) => (
                            <option key={n} value={n}>
                              {n}
                              {n < MIN_CPUS ? " (below min)" : ""}
                            </option>
                          ))}
                        </select>
                      </label>
                    </div>
                  );
                })
              )}
            </div>

            <p className="onboard-totals">
              Planned total: <b>{totalMb} MB</b> RAM · <b>{totalCpus}</b> CPUs
              {totalMb < HOST_FREE_RAM_GB * 1024 ? (
                <span className="onboard-totals-note">
                  {" "}
                  — under ~{HOST_FREE_RAM_GB} GB guest total; keep host free RAM
                  in mind.
                </span>
              ) : null}
            </p>
          </section>
        </div>

        {error && <p className="onboard-error">{error}</p>}

        <footer className="onboard-foot">
          <button
            className="btn btn-ghost"
            type="button"
            onClick={handleSkip}
            disabled={busy}
          >
            Skip for now
          </button>
          <button
            className="btn btn-accent"
            type="button"
            onClick={handleContinue}
            disabled={busy || underMin.length > 0}
          >
            {busy ? "Saving…" : "Save & open dashboard"}
          </button>
        </footer>
      </div>
    </div>
  );
}
