# Automation-VMs

Diagnostic app on a hardened multi-VM lab: containerized frontend/backend behind nginx, backup host, plus **Ansible + Jenkins CI/CD** on a dedicated `cicd` VM.

**Foundation:** Continues the Server Sorcery 101 hardening lab (users, SSH, UFW, umask, unattended upgrades). Guests live under `/opt/automation-alchemy`.

Idempotent Ansible config, local Docker registry, Jenkins pipeline (lint / audit / Trivy / deploy / rollback / Slack). See [`docs/alchemy.md`](docs/alchemy.md).

## Topology


| Host         | IP         | Role                                          |
| ------------ | ---------- | --------------------------------------------- |
| loadbalancer | 10.10.0.10 | nginx → web1/web2 (weighted RR or least_conn) |
| web1         | 10.10.0.11 | Frontend container (`:80`)                    |
| web2         | 10.10.0.12 | Frontend container (`:80`)                    |
| appserver    | 10.10.0.20 | Backend container (`:3000`, `/metrics`)       |
| backup       | 10.10.0.30 | Weekly full backups + restore helpers         |
| cicd         | 10.10.0.40 | Jenkins (`:8080`) + registry (`:5000`)        |


Private network: `10.10.0.0/24`. SSH user: `devops` (key in `keys/`, sudo password `devops`).

```text
Browser → loadbalancer:80 → web1|web2:80          (static UI)
                 └────────── /api → appserver:3000  (API direct)

Jenkins (cicd) → build/push → registry:5000 → ansible deploy → web/app
```



## Prerequisites

- VirtualBox + Vagrant
- Enough RAM for six VMs (~5 GB guest RAM + host headroom)
- **ansible** / **ansible-core** on the control host (for `make alchemy`)
- Optional: Node 22+ for local app/dashboard work



## Quick start (Alchemy — recommended)

```bash
make check-host          # host safety
make alchemy             # 6 VMs + Ansible + Jenkins + deploy
```

Open **[http://10.10.0.10/](http://10.10.0.10/)** and Jenkins at **[http://10.10.0.40:8080/](http://10.10.0.40:8080/)** (admin / `devops`).

## Quick start (Insight-only)

```bash
make create              # create + bash provision all VMs
make app-deploy          # docker save|load path (no registry)
make app-verify
```

Lab control UI (optional): `make dashboard`.

## Application

```text
app/
├── backend/     Express — GET /health, GET /metrics, GET /metrics/live
├── frontend/    React + Vite — served by nginx, proxies /api (local/direct)
└── docker-compose.yml   # local single-host reference
```

`/metrics` returns hostname, OS, uptime, memory, CPU, load, interfaces, and container hints.  
`/metrics/live` returns volatile fields only (memory, load, uptime) for cheap UI polling.

**Alchemy deploy:** images `aa-backend` / `aa-frontend` from `10.10.0.40:5000`.  
**Insight deploy:** `make app-deploy` still uses local build + save|load.

### Load balancing algorithms

Default is **weighted round-robin** (`web1` weight 3, `web2` weight 1).

```bash
make lb-algorithm ALG=least_conn
make lb-algorithm ALG=resource    # adaptive weights from web host CPU/memory
make lb-algorithm ALG=weighted    # restore default
curl -s http://10.10.0.10/lb-status
```

Configs: `config/nginx-lb.conf`, `config/nginx-lb.least_conn.conf`, `config/nginx-lb.resource.conf`.  
Resource mode runs `aa-lb-resource-adapt` on a 30s timer (disabled for other algorithms).

## Backup & restore

- Each app/web/lb host stages a daily root export under `/var/lib/automation-alchemy/backup-export/`.
- `backup` pulls weekly into `/var/backups/automation-alchemy/weekly/` (Sunday 02:30, keeps 4).
- Snapshots include **live-rsync’d** `/home/devops` trees plus `bundle.tar.gz` from daily export / `backup-now` (`/home/devops`, `/etc`, app data under `/var/lib/automation-alchemy`).
- Weekly dirs are `root:devops` mode `750` so devops can list with `aa-backup-list` / `make backup-list`.

```bash
make backup-now                      # export + pull now
make backup-list                     # list stamps as devops (sizes + home file counts)
make backup-restore                  # DRY-RUN only — nothing written
make backup-restore APPLY=1          # restore homes + app data
make backup-restore APPLY=1 WITH_ETC=1   # also restore /etc from bundles (opt-in)
```

Default `make backup-restore` is a dry-run. Files return only with `APPLY=1`. Overwriting live `/etc` requires `WITH_ETC=1`.

## Make targets


| Target                                       | Purpose                               |
| -------------------------------------------- | ------------------------------------- |
| `make alchemy`                               | One-click Phase 3 (Vagrant + Ansible + deploy) |
| `make rollback`                              | Redeploy last-known-good (or Jenkins `alchemy-rollback`) |
| `make setup-gitea-ci`                        | Print Git deploy-key / webhook checklist |
| `make verify-gitea-ci`                       | Check Git/Jenkins wiring readiness       |
| `make create` / `up`                         | Provision lab (bash bootstrap)        |
| `make destroy` / `reset` / `status` / `stop` | Lifecycle                             |
| `make verify` / `review`                     | Hardening + Docker/app/backup/cicd    |
| `make app-deploy` / `app-verify`             | Insight app path                      |
| `make backup-now` / `backup-list` / `backup-restore` | Backups (restore needs `APPLY=1`) |
| `make stretch*`                              | Opt-in Fail2Ban / WireGuard / Netdata |



## Project layout

```text
infrastructure/   Vagrantfile, machines.yml, network.yml
provisioning/     Modular guest bootstrap (incl. docker, lb, backup)
automation/       Ansible (site / cicd / deploy / rollback)
Jenkinsfile       CI pipeline on cicd (+ Jenkinsfile.rollback)
config/           sshd, ufw, nginx LB, hosts, umask
app/              Diagnostic product (frontend + backend)
dashboard/        Lab operator UI (not the product app)
scripts/          Host Make helpers (alchemy.sh, …)
tests/            One check per review item
security/         Stretch: fail2ban, wireguard
monitoring/       Stretch: netdata
```



## Extra features

- Responsive diagnostic UI with live status, skeletons, motion, and `prefers-reduced-motion`
- Weighted RR, least-connection, and **resource-based** LB (`make lb-algorithm ALG=…`) without changing default deploy
- Dedicated backup VM with automated weekly pull and scripted restore (homes + app data; `/etc` via `WITH_ETC=1`)
- Ansible idempotency + Jenkins CI (Git webhook) with rollback and optional Slack alerts

## Docs

| Doc | Contents |
|-----|----------|
| [docs/alchemy.md](docs/alchemy.md) | Phase 3 operator guide (Ansible, Jenkins, secrets) |
| [docs/how-to-run.md](docs/how-to-run.md) | Operator cheat sheet (lab + tunnels; no personal host IPs) |
| [docs/architecture.md](docs/architecture.md) | Components, provisioning flow, config sources |
| [docs/networking.md](docs/networking.md) | Adapters, address plan, UFW ports, WireGuard / Netdata |
| [docs/security.md](docs/security.md) | Hardening checklist + stretch demos |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common VirtualBox / SSH / UFW failures |
| [docs/roadmap.md](docs/roadmap.md) | Done vs deferred stretch |



## Security notes

- SSH: key-only, no root login, `devops` only on the private net (vagrant allowed from NAT)
- UFW: deny inbound by default; role overlays open only needed lab ports
- Jenkins/registry on `cicd` are lab-CIDR only (`10.10.0.0/24`)
- Default `make create` does not enable stretch extras
- Never commit secrets under `automation/secrets/` — copy from `*.example` files only
