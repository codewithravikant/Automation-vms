# How to run

Operator cheat sheet for the Automation-VMs lab.  
**Lab guest IPs** (`10.10.0.0/24`) are shared project topology.  
**Your laptop / hypervisor host addresses** stay out of git — use placeholders below or a private local note.

Placeholders used below:

| Placeholder | Meaning |
|-------------|---------|
| `LABHOST` | SSH Host alias (or `user@host`) for the machine that runs VirtualBox |
| `USER` | Login user on that machine |
| `HOST_IP` | LAN IP of that machine |
| `SSH_PORT` | SSH port (often `22` or a non-default) |

---

## 1. Prerequisites

On the VirtualBox host:

- VirtualBox + Vagrant
- ~5 GB free guest RAM for six VMs (incl. `cicd`)
- **ansible** / **ansible-core** (for `make alchemy`)
- Optional: Node 22+ (dashboard / local app work)

```bash
make check-host
```

---

## 2. SSH config (recommended)

On your **laptop** `~/.ssh/config` (do not commit this file):

```sshconfig
Host LABHOST
  HostName HOST_IP
  User USER
  Port SSH_PORT
  # IdentityFile ~/.ssh/id_ed25519
```

Then use `ssh LABHOST`. Set `SYNC_HOST` to that Host alias for `make sync-aiwin` and `make tunnels`.

---

## 3. Sync laptop → VirtualBox host

From the repo on your laptop:

```bash
make sync-aiwin
# or:
SYNC_HOST=LABHOST SYNC_REMOTE_DIR='~/automation-vms' ./scripts/sync-aiwin.sh
```

Remote path example: `~/automation-vms` (set `SYNC_REMOTE_DIR` if yours differs).

---

## 4. Create and run the lab (on the VirtualBox host)

```bash
cd ~/automation-vms   # your clone path on the VirtualBox host

make check-host
make alchemy                # recommended: 6 VMs + Ansible + Jenkins + deploy
# OR Insight-only:
# make create && make app-deploy

make status
make app-verify
make verify                 # hardening + docker/backup/cicd checks
make review                 # pretty reviewer output
```

Open (from the VirtualBox host network):

- App: http://10.10.0.10/
- Jenkins: http://10.10.0.40:8080/ (after `make alchemy`) — jobs `alchemy-app`, `alchemy-rollback`

Details: [alchemy.md](alchemy.md).

Rollback after a bad deploy:

```bash
make rollback
# or Build alchemy-rollback in Jenkins (TAG empty = previous)
```

Lifecycle:

```bash
make stop                   # power off VMs (disks kept)
make destroy                # wipe VMs
make reset                  # destroy + create
```

---

## 5. SSH into guests

Project key (created by `make create`):

```bash
ssh -i keys/id_ed25519 devops@10.10.0.10   # loadbalancer
ssh -i keys/id_ed25519 devops@10.10.0.11   # web1
ssh -i keys/id_ed25519 devops@10.10.0.12   # web2
ssh -i keys/id_ed25519 devops@10.10.0.20   # appserver
ssh -i keys/id_ed25519 devops@10.10.0.30   # backup
```

Operator / Vagrant path (from VirtualBox host):

```bash
cd infrastructure
vagrant ssh loadbalancer
vagrant ssh web1
# …
```

Sudo as `devops`: password `devops` (passwordless sudo is intentionally off).

---

## 6. Laptop tunnels (when VMs run on a remote host)

Start tunnels from your **laptop**:

```bash
# App (LB) + Dashboard + Jenkins CI
ssh -L 8080:10.10.0.10:80 \
    -L 13000:127.10.10.10:3030 \
    -L 18080:10.10.0.40:8080 \
    -p SSH_PORT USER@HOST_IP

# Same with Host alias:
ssh -L 8080:10.10.0.10:80 \
    -L 13000:127.10.10.10:3030 \
    -L 18080:10.10.0.40:8080 \
    LABHOST

# Netdata (after make stretch-monitor)
ssh -L 19999:10.10.0.10:19999 LABHOST
```

On the VirtualBox host, start the dashboard first:

```bash
make dashboard
# http://127.10.10.10:3030 on the host
```

| Service | Browser on laptop |
|---------|-------------------|
| Load balancer / app | http://localhost:8080 |
| Dashboard | http://localhost:13000 |
| **Jenkins CI** | http://localhost:18080 (admin / `devops`) |
| Netdata (LB) | http://localhost:19999 |

Jenkins and the registry listen only on the lab CIDR; always reach them via a tunnel through the VirtualBox host (never expose `:8080` / `:5000` publicly).

### CI/CD via Git webhook (short)

1. On host: `make alchemy` (once), then `make setup-gitea-ci` and follow the checklist.
2. Set `gitea_ssh_url` / `gitea_host` in `automation/inventory/group_vars/all.yml` to **your** Git forge.
3. On the VirtualBox host, create `automation/secrets/gitea_webhook` (and optional `slack_webhook`); re-run `ansible-playbook playbooks/cicd.yml`.
4. Install boot/webhook proxy: `sudo ./scripts/install-aiwin-boot-service.sh` (forge → host `:18081` path-only → Jenkins). Jenkins UI via laptop tunnel only.
5. `make verify-gitea-ci` on the VirtualBox host.
6. On laptop: open the tunnels above; push a `test/ci-sandbox/` change to your forge.
7. Watch http://localhost:18080/job/alchemy-app/ and confirm http://localhost:8080.
8. Rollback: `make rollback` on host, or job `alchemy-rollback`.

App pushes deploy the **CI registry tag** via Ansible (`deploy.yml`), not `make app-deploy`.  
`make sync-aiwin` remains as an optional/legacy rsync path; prefer Git webhook for CI demos.

Full Phase 3: [alchemy.md](alchemy.md).

### Share with a reviewer

Jenkins is not public. Pick one:

| Option | How |
|--------|-----|
| **A. Reviewer SSH to host** | Add their key on `LABHOST`; they run the same `-L` tunnels; open app + Jenkins on their localhost |
| **B. Screen share** | You keep tunnels open; share browser showing app + Jenkins |
| **C. Hop via your laptop** | Your tunnels stay up; reviewer SSHs to you and forwards `8080` / `18080` / `13000` |
| **D. Sit on host** | Open `http://10.10.0.10/` and `http://10.10.0.40:8080/` directly on the VirtualBox host |

Send them: tunnel command, Jenkins login (`admin` / `devops`), jobs `alchemy-app` + `alchemy-rollback`, and `make review` if they have a shell on the host.

---

## 7. Application / LB / backup

```bash
make app-deploy
make app-verify

make lb-algorithm ALG=weighted
make lb-algorithm ALG=least_conn
make lb-algorithm ALG=resource
curl -s http://10.10.0.10/lb-status

make backup-now
make backup-restore
make backup-restore APPLY=1
make backup-restore APPLY=1 WITH_ETC=1
```

---

## 8. Stretch extras (opt-in)

```bash
make stretch-ips        # Fail2Ban
make stretch-vpn        # WireGuard 10.66.0.0/24
make stretch-monitor    # Netdata :19999 (lab CIDR)
make stretch            # all three
```

Does **not** run during `make create`. Details: [security.md](security.md).

---

## 9. Reviewer cheatsheet

```bash
make check-host && make alchemy
# Insight-only alternative: make create && make app-deploy
make review
make app-verify
```

Guest checks as `devops`:

```bash
ssh -i keys/id_ed25519 devops@10.10.0.10
hostname; ip -br a
sudo -n true          # must fail
bash -lc umask        # expect 0027
sudo ufw status verbose
```

---

## Related docs

| Doc | Use |
|-----|-----|
| [architecture.md](architecture.md) | Topology + provision flow |
| [networking.md](networking.md) | Adapters, UFW, overlays |
| [security.md](security.md) | Hardening + stretch demos |
| [troubleshooting.md](troubleshooting.md) | VirtualBox / SSH / UFW fixes |
| [../dashboard/README.md](../dashboard/README.md) | Portfolio control UI |
