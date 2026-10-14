# Networking

## Adapters

Each VM has two adapters:

| Adapter | Mode | Purpose |
|---------|------|---------|
| 1 | NAT | Internet (apt, unattended-upgrades); Vagrant SSH |
| 2 | Private network `10.10.0.0/24` | Host ↔ VM and VM ↔ VM; review SSH as devops |

Defined in [`infrastructure/network.yml`](../infrastructure/network.yml) and applied by the Vagrantfile as `private_network` with a static IP.

## Address plan

| Hostname | IP |
|----------|-----|
| loadbalancer | 10.10.0.10 |
| web1 | 10.10.0.11 |
| web2 | 10.10.0.12 |
| appserver | 10.10.0.20 |
| backup | 10.10.0.30 |
| cicd | 10.10.0.40 |

Diagram: [`assets/topology.svg`](../assets/topology.svg)

## Hostname resolution

`provisioning/hosts.sh` writes a managed block into `/etc/hosts` on every guest (from `NETWORK_HOSTS` / [`config/hosts`](../config/hosts)):

```text
# BEGIN automation-alchemy
10.10.0.10 loadbalancer
10.10.0.11 web1
10.10.0.12 web2
10.10.0.20 appserver
10.10.0.30 backup
10.10.0.40 cicd
# END automation-alchemy
```

Re-provisioning replaces the managed block only (idempotent).

Verify:

```bash
hostname
ip a
ping -c 2 web1
ping -c 2 appserver
ping -c 2 backup
```

## Host access

From the host machine, use the private IPs directly:

```bash
ping 10.10.0.10
ssh -i keys/id_ed25519 devops@10.10.0.11
```

Optional: add the same `/etc/hosts` lines on the host for name-based SSH.

## Firewall and ports

Base UFW on every VM allows `22/tcp` ([`config/ufw.rules`](../config/ufw.rules)). Role overlays open only what each host needs:

| Host | Extra allows | Config |
|------|--------------|--------|
| loadbalancer | `80/tcp` (host / browser) | [`config/ufw.rules.loadbalancer`](../config/ufw.rules.loadbalancer) |
| web1 / web2 | `80/tcp` from `10.10.0.0/24` | [`config/ufw.rules.web1`](../config/ufw.rules.web1), [`web2`](../config/ufw.rules.web2) |
| appserver | `3000/tcp` from `10.10.0.0/24` | [`config/ufw.rules.appserver`](../config/ufw.rules.appserver) |
| backup | SSH already covered by base rules | [`config/ufw.rules.backup`](../config/ufw.rules.backup) |
| cicd | `8080/tcp` + `5000/tcp` from `10.10.0.0/24` | [`config/ufw.rules.cicd`](../config/ufw.rules.cicd) |

Traffic path after `make app-deploy`: browser → loadbalancer `:80` → web1/web2 frontend containers → `/api` → appserver `:3000`.

From the VirtualBox host:

```bash
curl -I http://10.10.0.10
# or open http://10.10.0.10 in a browser
```

From a laptop (SSH tunnels to the VirtualBox host — use placeholders from [`how-to-run.md`](how-to-run.md)):

```bash
ssh -L 13000:127.10.10.10:3030 -L 8080:10.10.0.10:80 -p SSH_PORT USER@HOST_IP
# or: ssh -L 13000:127.10.10.10:3030 -L 8080:10.10.0.10:80 LABHOST
```

| Service | Browser URL |
|---------|-------------|
| Dashboard | http://localhost:13000 |
| Load balancer | http://localhost:8080 |

## Stretch: WireGuard overlay

Opt-in (`make stretch-vpn`). Does not change default UFW templates.

| Role | Host | WireGuard IP | Notes |
|------|------|--------------|-------|
| Hub | loadbalancer | 10.66.0.10 | `51820/udp` allowed on hub |
| Spoke | web1 | 10.66.0.11 | Endpoint → `10.10.0.10:51820` |
| Spoke | web2 | 10.66.0.12 | |
| Spoke | appserver | 10.66.0.20 | |
| Spoke | backup | 10.66.0.30 | |

Configs: `keys/wireguard/` (gitignored). Details: [`security/README.md`](../security/README.md).

## Stretch: Netdata

Opt-in (`make stretch-monitor`). Opens `19999/tcp` from `10.10.0.0/24` only on every VM (including backup).
See [`monitoring/README.md`](../monitoring/README.md).
