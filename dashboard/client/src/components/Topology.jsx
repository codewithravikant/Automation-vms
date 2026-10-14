const FLOW = [
  {
    id: "host",
    label: "Host",
    sub: "Dashboard / Internet",
    kind: "edge",
    x: 24,
    y: 118,
    w: 110,
    h: 56,
  },
  {
    id: "loadbalancer",
    label: "loadbalancer",
    kind: "vm",
    x: 190,
    y: 118,
    w: 140,
    h: 56,
  },
  {
    id: "web1",
    label: "web1",
    kind: "vm",
    x: 390,
    y: 48,
    w: 120,
    h: 56,
  },
  {
    id: "web2",
    label: "web2",
    kind: "vm",
    x: 390,
    y: 188,
    w: 120,
    h: 56,
  },
  {
    id: "appserver",
    label: "appserver",
    kind: "vm",
    x: 570,
    y: 118,
    w: 130,
    h: 56,
  },
  {
    id: "cicd",
    label: "cicd",
    kind: "vm",
    x: 570,
    y: 210,
    w: 130,
    h: 56,
  },
];

const EDGES = [
  ["host", "loadbalancer"],
  ["loadbalancer", "web1"],
  ["loadbalancer", "web2"],
  ["web1", "appserver"],
  ["web2", "appserver"],
  ["cicd", "appserver"],
];

/** Edges that are “live” when a given VM is selected */
function liveEdgeIds(selected) {
  if (!selected) return new Set();
  if (selected === "loadbalancer") {
    return new Set(["host-loadbalancer"]);
  }
  if (selected === "web1") {
    return new Set(["host-loadbalancer", "loadbalancer-web1"]);
  }
  if (selected === "web2") {
    return new Set(["host-loadbalancer", "loadbalancer-web2"]);
  }
  if (selected === "appserver") {
    return new Set([
      "host-loadbalancer",
      "loadbalancer-web1",
      "loadbalancer-web2",
      "web1-appserver",
      "web2-appserver",
    ]);
  }
  if (selected === "cicd") {
    return new Set(["cicd-appserver"]);
  }
  return new Set();
}

function nodeCenter(id) {
  const n = FLOW.find((x) => x.id === id);
  return { x: n.x + n.w / 2, y: n.y + n.h / 2 };
}

function stateColor(state, reachable) {
  if (state === "running" && reachable) return "var(--ok)";
  if (state === "running") return "var(--warn)";
  if (state === "poweroff" || state === "aborted") return "var(--muted)";
  if (state === "not_created") return "var(--muted)";
  return "var(--warn)";
}

export default function Topology({ machines, selected, onSelect }) {
  const byName = Object.fromEntries(machines.map((m) => [m.name, m]));
  const live = liveEdgeIds(selected);
  const selectedMachine = byName[selected];

  return (
    <div className="topo-wrap">
      <svg
        className="topo-svg"
        viewBox="0 0 720 290"
        role="img"
        aria-label="Automation-VMs live network topology"
      >
        <defs>
          <marker
            id="topo-arrow"
            markerWidth="8"
            markerHeight="8"
            refX="6"
            refY="3"
            orient="auto"
          >
            <path d="M0,0 L6,3 L0,6 Z" fill="currentColor" />
          </marker>
          <marker
            id="topo-arrow-live"
            markerWidth="8"
            markerHeight="8"
            refX="6"
            refY="3"
            orient="auto"
          >
            <path d="M0,0 L6,3 L0,6 Z" fill="var(--accent)" />
          </marker>
        </defs>

        {EDGES.map(([a, b]) => {
          const from = nodeCenter(a);
          const to = nodeCenter(b);
          const id = `${a}-${b}`;
          const isLive = live.has(id);
          return (
            <line
              key={id}
              className={`topo-edge${isLive ? " live" : ""}`}
              x1={from.x}
              y1={from.y}
              x2={to.x}
              y2={to.y}
              markerEnd={isLive ? "url(#topo-arrow-live)" : "url(#topo-arrow)"}
            />
          );
        })}

        {FLOW.map((n) => {
          if (n.kind === "edge") {
            return (
              <g key={n.id} className="topo-node topo-host">
                <rect x={n.x} y={n.y} width={n.w} height={n.h} rx="10" />
                <text x={n.x + n.w / 2} y={n.y + 24} textAnchor="middle">
                  {n.label}
                </text>
                <text
                  x={n.x + n.w / 2}
                  y={n.y + 42}
                  textAnchor="middle"
                  className="topo-sub"
                >
                  {n.sub}
                </text>
              </g>
            );
          }

          const m = byName[n.id];
          const active = selected === n.id;
          const state = m?.state || "unknown";
          const accent = stateColor(state, m?.reachable);

          return (
            <g
              key={n.id}
              className={`topo-node topo-vm${active ? " active" : ""}`}
              onClick={() => onSelect(n.id)}
              style={{ cursor: "pointer" }}
            >
              <rect
                x={n.x}
                y={n.y}
                width={n.w}
                height={n.h}
                rx="10"
                style={{ stroke: active ? "var(--accent)" : undefined }}
              />
              <circle
                cx={n.x + 14}
                cy={n.y + 16}
                r="4"
                fill={accent}
                style={{ filter: `drop-shadow(0 0 4px ${accent})` }}
              />
              <text x={n.x + 26} y={n.y + 20}>
                {n.label}
              </text>
              <text x={n.x + 14} y={n.y + 40} className="topo-sub">
                {m?.ip || "—"} · {String(state).replace("_", " ")}
              </text>
            </g>
          );
        })}
      </svg>

      <p className="topo-status">
        {selectedMachine ? (
          <>
            Live focus: <strong>{selectedMachine.name}</strong> ·{" "}
            {selectedMachine.ip} · {String(selectedMachine.state).replace("_", " ")}
            {selectedMachine.reachable ? " · reachable" : ""}
          </>
        ) : (
          <>Private network 10.10.0.0/24 · select a node for live path</>
        )}
      </p>
    </div>
  );
}
