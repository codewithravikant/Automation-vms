# Screenshots

Evidence that the Automation-VMs lab is running end to end. These files are tracked in git.

| File | What it shows |
|------|----------------|
| [`dashboard-frontpage.png`](dashboard-frontpage.png) | Control dashboard home: lab VMs running, topology map, and live terminal |
| [`netdata.png`](netdata.png) | Netdata monitoring UI on the loadbalancer (CPU, RAM, network live charts) |
| [`make-review.png`](make-review.png) | `make review` output: all Layer 1 checks passed on loadbalancer |

## Dashboard front page

![Dashboard front page](dashboard-frontpage.png)

The Automation-VMs control plane in the browser (`http://localhost:13000` via SSH tunnel). Guests — loadbalancer, web1, web2, appserver, and backup — show as running and reachable. The topology panel matches the lab network, and the bottom panel is a browser SSH terminal into the selected VM.

## Netdata

![Netdata monitoring](netdata.png)

Live metrics from Netdata on the loadbalancer (`http://localhost:19999` via SSH tunnel). You do not need to sign in to Netdata Cloud for the lab Extra; the local agent UI is enough.

## Make review result

![Make review passed](make-review.png)

Terminal output of `make review` on the host. Hostname, static IP, SSH hardening, UFW, devops/sudo, umask, and unattended-upgrades all passed (17 passed, 0 failed on the loadbalancer sample shown).
