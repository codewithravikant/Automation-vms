#!/usr/bin/env bash
# Print one-time Git → Jenkins CI setup checklist for this lab.
# Also reports local readiness (keys, secrets, scripts).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUB="${ROOT}/keys/id_ed25519.pub"
PRIV="${ROOT}/keys/id_ed25519"
SECRET_FILE="${ROOT}/automation/secrets/gitea_webhook"
SLACK_FILE="${ROOT}/automation/secrets/slack_webhook"
HOST_IP="${LAB_HOST_IP:-<your-virtualbox-host-ip>}"
WEBHOOK_PORT="${WEBHOOK_PROXY_PORT:-18081}"

echo "========================================"
echo " Git → Jenkins setup checklist"
echo "========================================"
echo ""
echo "Repo: set gitea_ssh_url / gitea_https_url in automation/inventory/group_vars/all.yml"
echo "      (placeholders: git.example.com / your-org/automation-vms)"
echo ""
echo "Ports:"
echo "  Webhook (Git forge → VirtualBox host):  :${WEBHOOK_PORT}  path /generic-webhook-trigger/ only"
echo "  Jenkins UI (laptop tunnel): localhost:18080 → 10.10.0.40:8080"
echo ""
echo "1) Deploy key (read-only) on your Git forge"
if [[ -f "${PUB}" ]]; then
  echo "   Add this public key as a Deploy Key (read-only):"
  echo "   ----------------------------------------"
  cat "${PUB}"
  echo "   ----------------------------------------"
else
  echo "   Missing ${PUB} — run make alchemy / ensure-ssh-key first (on the VirtualBox host)"
fi
if [[ -f "${PRIV}" ]]; then
  echo "   Private key present (Jenkins/cicd will use a copy)."
else
  echo "   Private key missing locally — expected on the VirtualBox host under keys/ after alchemy."
fi
echo ""
echo "2) Webhook secret file on the VirtualBox host (gitignored)"
echo "   cp automation/secrets/gitea_webhook.example automation/secrets/gitea_webhook"
echo "   # one long random token, same value as the forge webhook ?token="
if [[ -f "${SECRET_FILE}" ]]; then
  echo "   Found: ${SECRET_FILE}"
else
  echo "   Not found yet: ${SECRET_FILE}"
fi
echo ""
echo "3) Optional Slack alerts (gitignored token/URL → #jenkins-builds)"
echo "   cp automation/secrets/slack_webhook.example automation/secrets/slack_webhook"
echo "   # one line: xoxb-...  or https://hooks.slack.com/services/..."
if [[ -f "${SLACK_FILE}" ]]; then
  echo "   Found: ${SLACK_FILE}"
else
  echo "   Not found (notifications will be skipped): ${SLACK_FILE}"
fi
echo ""
echo "4) On the VirtualBox host — authorize Jenkins SSH (same deploy pubkey):"
echo "   grep -qf keys/id_ed25519.pub ~/.ssh/authorized_keys || cat keys/id_ed25519.pub >> ~/.ssh/authorized_keys"
echo ""
echo "5) Clone/pull on the host must track your Git forge:"
echo "   git remote -v"
echo "   # origin → value of gitea_ssh_url in group_vars/all.yml"
echo ""
echo "6) Install boot + webhook proxy:"
echo "   sudo ./scripts/install-aiwin-boot-service.sh"
echo "   sudo ufw allow ${WEBHOOK_PORT}/tcp comment 'git webhook proxy'"
echo "   # Prefer: sudo ufw allow from <git-forge-ip> to any port ${WEBHOOK_PORT} proto tcp"
echo ""
echo "7) Re-seed Jenkins (picks up webhook token + SCM URL):"
echo "   cd automation && ansible-playbook playbooks/cicd.yml"
echo ""
echo "8) Git forge webhook (repo Settings → Webhooks):"
echo "   URL:  http://${HOST_IP}:${WEBHOOK_PORT}/generic-webhook-trigger/invoke?token=<same-secret>"
echo "   HTTP Method: POST"
echo "   Trigger: Push events"
echo "   (port ${WEBHOOK_PORT} is webhook-ONLY — Jenkins UI is not exposed there)"
echo ""
echo "9) Jenkins UI from laptop: keep an SSH tunnel open (see docs/how-to-run.md):"
echo "   ssh -L 18080:10.10.0.40:8080 … → http://localhost:18080"
echo ""
echo "10) From cicd, the VirtualBox host must be reachable as AIWIN_SSH_HOST (default 10.10.0.1)."
echo "    Override AIWIN_SSH_USER / AIWIN_SSH_PORT / AIWIN_PROJECT if needed."
echo ""
echo "11) Prove demos:"
echo "    make verify-gitea-ci          # local readiness + classify smoke"
echo "    # app:   edit test/ci-sandbox/TRIGGER.txt → commit → push → alchemy-app"
echo "    # infra: touch automation/… → push → make alchemy on host"
echo "    # docs:  docs-only commit → skip"
echo "    # boot:  reboot host → VMs + :${WEBHOOK_PORT} proxy, no alchemy"
echo ""
echo "Done printing checklist. Next: make verify-gitea-ci"
