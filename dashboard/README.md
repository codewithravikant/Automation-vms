# Dashboard (Layer 3 — portfolio UI)

Primary control plane for Automation-VMs. Visualizes the Vagrant stack, drives
VM lifecycle actions, and opens browser SSH as `devops` — it does **not** replace
manual SSH review.

## Quick start (run this first)

From the repo root:

```bash
make dashboard          # install deps if needed, then start http://127.10.10.10:3030
# or development (API + Vite HMR):
make dashboard-dev
```

From this directory:

```bash
npm install
npm run dev            # Express 127.10.10.10:3030 + Vite :5173 (proxied)
# production:
npm run build && npm start
```

Open **http://127.10.10.10:3030** (prod) or **http://localhost:5173** (dev UI).

### From a laptop

If the dashboard runs on a remote VirtualBox host, tunnel to a free local port (avoid laptop `:3000`).

Use placeholders from [`docs/how-to-run.md`](../docs/how-to-run.md):

```bash
ssh -L 13000:127.10.10.10:3030 -p SSH_PORT USER@HOST_IP
# open http://localhost:13000
```

With load balancer in the same session:

```bash
ssh -L 13000:127.10.10.10:3030 -L 8080:10.10.0.10:80 -p SSH_PORT USER@HOST_IP
# or Host alias: ssh -L 13000:127.10.10.10:3030 -L 8080:10.10.0.10:80 LABHOST
```

| Service | Browser URL |
|---------|-------------|
| Dashboard | http://localhost:13000 |
| Load balancer | http://localhost:8080 |

Full operator cheat sheet: [`docs/how-to-run.md`](../docs/how-to-run.md).

The API binds a project-unique loopback IP so other apps on `localhost:3000` are left alone. If that port is busy, the next free port is used and printed in the terminal. On macOS, `make dashboard` runs [`scripts/ensure-dashboard-host.sh`](../scripts/ensure-dashboard-host.sh) to add the `lo0` alias (may ask for your password once).

## Features

- Dual-tone **dark / light** theme
- Per-VM status (Vagrant state + ping)
- Customize **CPU / RAM** → writes [`infrastructure/machines.yml`](../infrastructure/machines.yml) (Vagrantfile source of truth); **Save & apply** runs `vagrant reload`
- Start / Stop / Restart / Provision / Destroy (wraps `vagrant` in `infrastructure/`)
- Topology diagram (select a VM)
- Integrated **xterm.js** terminal → SSH as `devops` with `keys/id_ed25519`
- **Run validation** → `./scripts/verify.sh`

## Stack

| Layer | Tech |
|-------|------|
| UI | Vite + React |
| API | Express on `127.10.10.10:3030` (auto next port if busy) |
| Terminal | WebSocket + `ssh2` + xterm.js |
| Source of truth | `infrastructure/machines.yml` |

## Rules

1. Assignment commands remain the source of truth (`make create|verify|review`).
2. Dashboard credentials must not weaken SSH hardening (key-only `devops`, no root).
3. Generate the project key before terminals work: `make create` (or keygen via create script).
