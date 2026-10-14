# Monitoring stretch helpers

Optional only — **not** part of `make create` / bootstrap.

| Path | Purpose |
|------|---------|
| `netdata.sh` | Install Netdata (kickstart), enable service on `:19999` |
| `prometheus/` | Placeholder for a future scrape stretch |

## Netdata

```bash
make stretch-monitor
```

That runs Netdata on every VM and opens UFW for `19999/tcp` **from `10.10.0.0/24` only**.

Install order inside `netdata.sh`:

1. Official kickstart `--install-type static` (HTTPS — preferred; lab NAT often breaks apt HTTP :80)
2. Ubuntu `apt install netdata` as fallback

If install fails, from a guest compare:

```bash
curl -I --connect-timeout 5 http://archive.ubuntu.com/ubuntu/
curl -I --connect-timeout 5 https://get.netdata.cloud/
```

Manual:

```bash
sudo STRETCH_OPEN_UFW=1 bash /opt/automation-alchemy/monitoring/netdata.sh
```

UI examples (from VirtualBox host):

| VM | URL |
|----|-----|
| loadbalancer | http://10.10.0.10:19999 |
| web1 | http://10.10.0.11:19999 |
| web2 | http://10.10.0.12:19999 |
| appserver | http://10.10.0.20:19999 |
| backup | http://10.10.0.30:19999 |
