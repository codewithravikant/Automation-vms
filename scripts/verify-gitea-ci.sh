#!/usr/bin/env bash
# Verify Git → Jenkins wiring readiness (local checks + optional live probes).
# Does NOT run make alchemy. Safe to run on laptop or VirtualBox host.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=_common.sh
source "${ROOT}/scripts/_common.sh" 2>/dev/null || true

PUB="${ROOT}/keys/id_ed25519.pub"
PRIV="${ROOT}/keys/id_ed25519"
SECRET_FILE="${ROOT}/automation/secrets/gitea_webhook"
SLACK_FILE="${ROOT}/automation/secrets/slack_webhook"
WEBHOOK_PORT="${WEBHOOK_PROXY_PORT:-18081}"
JENKINS_URL="${JENKINS_URL:-http://10.10.0.40:8080}"
REGISTRY_URL="${REGISTRY_URL:-http://10.10.0.40:5000/v2/}"
LB_URL="${LB_URL:-http://10.10.0.10/}"
FAILS=0

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }
warn() { echo "  WARN  $*"; }
info() { echo "  ----  $*"; }

echo "========================================"
echo " Automation-VMs — verify Git CI"
echo "========================================"

echo ""
echo "==> Repo scripts"
if [[ -x "${ROOT}/scripts/classify-git-changes.sh" ]]; then
  pass "classify-git-changes.sh executable"
else
  fail "classify-git-changes.sh missing or not executable"
fi
if [[ -x "${ROOT}/scripts/jenkins-remote-make.sh" ]]; then
  pass "jenkins-remote-make.sh executable"
else
  fail "jenkins-remote-make.sh missing or not executable"
fi
if [[ -x "${ROOT}/scripts/aiwin-boot-ensure.sh" ]]; then
  pass "aiwin-boot-ensure.sh executable"
else
  fail "aiwin-boot-ensure.sh missing or not executable"
fi
if [[ -f "${ROOT}/Jenkinsfile" ]]; then
  if grep -q 'IMAGE_TAG' "${ROOT}/Jenkinsfile" && grep -q 'ansible-playbook playbooks/deploy.yml' "${ROOT}/scripts/jenkins-remote-make.sh"; then
    pass "App path deploys registry tag via Ansible (not make app-deploy)"
  else
    fail "App path still looks like Insight make app-deploy — check Jenkinsfile / jenkins-remote-make.sh"
  fi
else
  fail "Jenkinsfile missing"
fi

echo ""
echo "==> Path classifier smoke"
MODE="$(bash "${ROOT}/scripts/classify-git-changes.sh" 2>/dev/null || echo fail)"
case "${MODE}" in
  skip|app|infra) pass "classify-git-changes.sh → ${MODE}" ;;
  *) fail "classify-git-changes.sh returned unexpected: ${MODE}" ;;
esac

echo ""
echo "==> Secrets / keys (local tree)"
if [[ -f "${PUB}" ]]; then
  pass "Deploy pubkey present: keys/id_ed25519.pub"
else
  warn "Deploy pubkey missing here (ok on laptop if keys live on the VirtualBox host)"
fi
if [[ -f "${PRIV}" ]]; then
  pass "Deploy private key present"
else
  warn "Deploy private key missing here (ok on laptop if keys live on the VirtualBox host)"
fi
if [[ -f "${SECRET_FILE}" ]]; then
  TOKEN="$(tr -d '[:space:]' < "${SECRET_FILE}" | head -n1 || true)"
  if [[ -n "${TOKEN}" && "${TOKEN}" != \#* && "${TOKEN}" != CHANGE_ME ]]; then
    pass "gitea_webhook secret file set"
  else
    fail "gitea_webhook exists but token looks empty/placeholder"
  fi
else
  warn "Missing automation/secrets/gitea_webhook — required on host before live webhook demos"
  warn "  cp automation/secrets/gitea_webhook.example automation/secrets/gitea_webhook"
fi
if [[ -f "${SLACK_FILE}" ]]; then
  SLACK_SECRET="$(grep -v '^[[:space:]]*#' "${SLACK_FILE}" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]' || true)"
  if [[ "${SLACK_SECRET}" == xoxb-* ]]; then
    pass "slack_webhook bot token present (Slack plugin / #jenkins-builds)"
  elif [[ "${SLACK_SECRET}" == https://hooks.slack.com/* ]]; then
    pass "slack_webhook Incoming Webhook present (legacy script alerts)"
  else
    warn "slack_webhook present but not an xoxb- token or hooks.slack.com URL"
  fi
else
  warn "slack_webhook missing (alerts skipped — optional)"
fi

echo ""
echo "==> Live probes (skip quietly if lab down)"
if curl -fsS --max-time 3 -o /dev/null "${JENKINS_URL}/login" 2>/dev/null; then
  pass "Jenkins reachable at ${JENKINS_URL}"
else
  warn "Jenkins not reachable at ${JENKINS_URL} (tunnel or lab offline)"
fi
if curl -fsS --max-time 3 -o /dev/null "${REGISTRY_URL}" 2>/dev/null; then
  pass "Registry reachable at ${REGISTRY_URL}"
else
  warn "Registry not reachable"
fi
if curl -fsS --max-time 3 -o /dev/null "${LB_URL}" 2>/dev/null; then
  pass "App LB reachable at ${LB_URL}"
else
  warn "App LB not reachable"
fi

# Webhook proxy: only meaningful on the VirtualBox host
PROXY_URL="http://127.0.0.1:${WEBHOOK_PORT}/"
if curl -fsS --max-time 2 -o /dev/null "${PROXY_URL}" 2>/dev/null \
  || curl -sS --max-time 2 -o /dev/null -w '' "${PROXY_URL}" 2>/dev/null; then
  # Path root should 403; that still means nginx is up
  CODE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 "${PROXY_URL}" || echo 000)"
  if [[ "${CODE}" == "403" || "${CODE}" == "200" || "${CODE}" == "404" ]]; then
    pass "Webhook proxy responds on :${WEBHOOK_PORT} (HTTP ${CODE})"
  else
    warn "Something on :${WEBHOOK_PORT} returned HTTP ${CODE}"
  fi
else
  info "Webhook proxy :${WEBHOOK_PORT} not local — install via install-aiwin-boot-service.sh"
fi

echo ""
echo "==> Demo commands (run after wiring)"
cat <<'EOF'
  # App path (safe sandbox):
  echo "ping $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> test/ci-sandbox/TRIGGER.txt
  git add test/ci-sandbox/ && git commit -m "ci-sandbox: trigger app pipeline" && git push

  # Docs-only skip:
  # edit docs/alchemy.md → commit → push → expect DEPLOY_MODE=skip

  # Infra path:
  # touch automation/… → commit → push → expect make alchemy on VirtualBox host

  # Boot (on VirtualBox host):
  # sudo systemctl restart alchemy-boot-ensure.service
  # journalctl -u alchemy-boot-ensure.service -n 50  # must NOT mention make alchemy
EOF

echo ""
if [[ "${FAILS}" -gt 0 ]]; then
  echo "RESULT: ${FAILS} required check(s) failed"
  exit 1
fi
echo "RESULT: readiness OK (complete live demos on VirtualBox host + Git forge)"
exit 0
