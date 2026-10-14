# Security stretch helpers

Hardening templates live in [`config/`](../config/) (sshd, UFW, umask, auto-upgrades, hosts).

This directory holds **optional** stretch scripts. They are **not** called by
`provisioning/bootstrap.sh` or `make create`. Use Make targets (or run on a guest).

| Script | Purpose |
|--------|---------|
| `fail2ban.sh` | Install Fail2Ban + SSH jail |
| `wireguard-gen.sh` | Generate WireGuard keys/configs into `keys/wireguard/` |
| `wireguard-apply.sh` | Install peer config and start `wg-quick@wg0` |

## Intrusion prevention (Fail2Ban)

```bash
make stretch-ips
# or on a guest:
sudo bash /opt/automation-alchemy/security/fail2ban.sh
```

## VPN (WireGuard)

Hub-spoke overlay `10.66.0.0/24` with **loadbalancer** as hub (`51820/udp`).

```bash
make stretch-vpn
```

Manual equivalent:

```bash
# on loadbalancer
sudo bash /opt/automation-alchemy/security/wireguard-gen.sh
# on every VM
sudo bash /opt/automation-alchemy/security/wireguard-apply.sh
```

Keys and peer configs land under `keys/wireguard/` (gitignored). Verify:

```bash
vagrant ssh loadbalancer -c 'sudo wg show'
vagrant ssh loadbalancer -c 'ping -c 2 10.66.0.11'
```
