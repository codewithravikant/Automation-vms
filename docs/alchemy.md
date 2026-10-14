# Automation-VMs (Phase 3)

Ansible + Jenkins CI/CD on top of the Vagrant lab. Blank slate → live app:

```bash
make alchemy
```

## Tool choice (oral review)

| Concern | Choice | Why (short) |
|---------|--------|-------------|
| VM create | **Vagrant** (+ VirtualBox) | Keeps Phase 1/2 summoning; Terraform cloud out of scope |
| Config / harden / deploy | **Ansible** | Agentless, SSH + key already in `keys/`, idempotent modules, easy rollback playbooks |
| vs Puppet | — | Puppet needs agents + master story; heavier for a 6-VM laptop lab |
| vs Terraform for guests | — | We already own Vagrant inventory; Terraform adds little for local VirtualBox |
| CI/CD | **Jenkins** on `cicd` | Classic pipeline demo, JCasC-seeded job, runs on a **separate** VM in the flow |
| vs GitLab/CircleCI | — | Would pull the lab toward SaaS/external runners; local Jenkins keeps demos offline |
| Alerts | **Slack Incoming Webhook** | One secret file; optional — pipeline skips if missing |

## Topology addition

| Host | IP | Role |
|------|-----|------|
| …existing five… | … | … |
| **cicd** | **10.10.0.40** | Jenkins `:8080` + Docker registry `:5000` (~2 GB RAM) |

UFW on `cicd`: `8080` and `5000` only from `10.10.0.0/24`. Load balancer remains the only external HTTP entry (`:80`).

## Prerequisites (control host)

- VirtualBox + Vagrant (same as Insight)
- **ansible** / **ansible-core** (`brew install ansible` or `pip install ansible`)
- RAM for **six** guests (~5 GB guest RAM + ~1 GB headroom)
- Optional: Slack webhook file (see Secrets)

## One-click

```bash
make check-host
make alchemy
```

`scripts/alchemy.sh` will:

1. Safety check + ensure `keys/id_ed25519`
2. `vagrant up` (6 VMs; Phase 1/2 bash bootstrap still runs)
3. Wait for `devops` SSH
4. `ansible-playbook playbooks/site.yml` (harden / docker / LB / backup)
5. `ansible-playbook playbooks/cicd.yml` (Jenkins + registry + Trivy)
6. Build/push `aa-backend` / `aa-frontend` to `10.10.0.40:5000`
7. `ansible-playbook playbooks/deploy.yml`
8. Smoke via `make app-verify` helpers

URLs:

- App: http://10.10.0.10/
- Jenkins: http://10.10.0.40:8080/ (admin / `devops`)
- Registry: `10.10.0.40:5000`

## Ansible layout

```text
automation/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml
│   └── group_vars/all.yml
├── playbooks/
│   ├── site.yml       # common + docker + lb + backup
│   ├── cicd.yml       # Jenkins + registry
│   ├── deploy.yml     # pull tags + run containers + record version
│   └── rollback.yml   # redeploy PREVIOUS_TAG
└── roles/
    ├── common/
    ├── docker/
    ├── loadbalancer/
    ├── backup/
    ├── app_deploy/
    └── cicd/
```

**Idempotency demo:** from the control host:

```bash
cd automation
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/site.yml   # expect mostly changed=0 / ok
```

## Pipeline (Jenkins)

Jobs seeded by init groovy:

| Job | Purpose |
|-----|---------|
| `alchemy-app` | Git webhook CI: path detect → app or infra deploy |
| `alchemy-rollback` | Manual demo: empty `TAG` → `PREVIOUS_TAG`; or redeploy a specific tag |

Triggers: **Git forge push webhook** (instant) → VirtualBox host `:18081` nginx (path `/generic-webhook-trigger/` only) → Jenkins Generic Webhook Trigger (secret in `automation/secrets/gitea_webhook`), plus **SCM poll every minute** against your forge (runs only when commits changed). Jenkins UI stays tunnel-only (`localhost:18080` → `10.10.0.40:8080`).

`alchemy-app` is **Pipeline from SCM** (URL in `automation/inventory/group_vars/all.yml`):

1. Checkout from Git (SSH deploy key = `keys/id_ed25519`, read-only on the forge)
2. **Detect path changes** — `scripts/classify-git-changes.sh` (`git diff HEAD~1 HEAD`)
   - docs / README / LICENSE only → **skip**
   - `app/` only → **app** path
   - `automation/` (alone or with `app/`) → **infra** path (`make alchemy`)
   - first commit → **infra**
3. **App path:** ESLint → `npm test` → `npm audit` → Docker build/push → Trivy → SSH to the VirtualBox host → `git pull` + `ansible-playbook playbooks/deploy.yml -e image_tag=<sha>` + `make app-verify` → smoke/perf → Slack  
   (`make app-deploy` is Insight-only; CI deploys the **registry** `aa-*` tag so rollback stays consistent.)
4. **Infra path:** SSH to the VirtualBox host → `git pull` + `make alchemy` → Slack
5. On app failure — auto `playbooks/rollback.yml` + Slack

`make alchemy` stays one-click for blank slate / infra. Do **not** run it on every boot.

Boot on the VirtualBox host: `sudo ./scripts/install-aiwin-boot-service.sh` — brings VMs + webhook proxy up; **never** runs `make alchemy`.

Setup checklist: `make setup-gitea-ci`.

Rollback:

```bash
make rollback
# or Jenkins job alchemy-rollback (TAG optional)
```

Last-known-good SHA is stored on cicd at `/var/lib/automation-alchemy/deployed_version`.

## Secrets

```bash
cp automation/secrets/slack_webhook.example automation/secrets/slack_webhook
# paste a single Slack Bot User OAuth Token (xoxb-..., one line)
# or an Incoming Webhook URL — never commit this file
# invite the bot to the channel named in group_vars (slack_channel)

cp automation/secrets/gitea_webhook.example automation/secrets/gitea_webhook
# paste one-line shared token (same value in forge webhook ?token=)
```

Files are gitignored. Missing Slack token → `slackSend` fails softly. Missing webhook token → placeholder credential until you set the file and re-run `cicd.yml`. Workspace, channel, and credential id live in `automation/inventory/group_vars/all.yml` (`slack_team_domain`, `slack_channel`, `slack_credential_id`) — use placeholders, not personal workspace names.

## Insight-only path (unchanged)

Phases 1–2 demos still work without Alchemy:

```bash
make create
make app-deploy    # docker save|load (no registry)
make app-verify
```

## Review checklist mapping

| Demo | How |
|------|-----|
| Blank slate, no manual steps | `make alchemy` |
| ≥5 VMs + names/IPs | 6 VMs incl. `cicd` |
| Automation + CI proficiency | Ansible roles + Jenkins on dedicated VM |
| App + metrics | http://10.10.0.10/ + `/api/metrics` |
| Idempotency | re-run `site.yml` |
| CI tracks change → deploy | `git push` → webhook → `alchemy-app` (or FORCE_APP) |
| Tests / rollback / alerts / one-click | audit/Trivy + `alchemy-rollback` / `make rollback` + Slack + `make alchemy` |
| Phase 1 hardening on every VM | still true, including `cicd` |
