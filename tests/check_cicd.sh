#!/usr/bin/env bash
# Check: Jenkins + registry on cicd (skips quietly if cicd not present / Insight-only).
# When Jenkins HTTP is up (Alchemy applied), registry + jobs are required.
# Usage: check_cicd.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

if [[ "${NAME}" != "cicd" ]]; then
  pass "cicd check N/A (${NAME})"
  exit 0
fi

jenkins_http=0
if curl -fsS --max-time 5 -o /dev/null -w '' "http://${IP}:8080/login" 2>/dev/null \
  || curl -fsS --max-time 5 -o /dev/null -w '' "http://${IP}:8080/" 2>/dev/null; then
  jenkins_http=1
  pass "Jenkins HTTP on ${IP}:8080"
else
  if remote "${IP}" "systemctl is-active jenkins >/dev/null 2>&1" >/dev/null 2>&1; then
    fail "Jenkins HTTP reachable (${NAME})"
    exit 1
  fi
  # Insight-only: cicd VM may exist without Alchemy applied yet
  pass "Jenkins not configured yet (${NAME}) — run make alchemy"
  exit 0
fi

# Alchemy is applied (Jenkins responds) — require registry + seeded jobs
if curl -fsS --max-time 5 "http://${IP}:5000/v2/" >/dev/null 2>&1; then
  pass "Docker registry on ${IP}:5000"
else
  fail "Docker registry HTTP (${NAME}) — expected after make alchemy"
  exit 1
fi

if remote "${IP}" "test -f /var/lib/jenkins/jobs/alchemy-app/config.xml -o -d /var/lib/jenkins/jobs/alchemy-app" >/dev/null 2>&1; then
  pass "Jenkins job alchemy-app present"
else
  fail "Jenkins job alchemy-app missing (${NAME})"
  exit 1
fi

if remote "${IP}" "test -f /var/lib/jenkins/jobs/alchemy-rollback/config.xml -o -d /var/lib/jenkins/jobs/alchemy-rollback" >/dev/null 2>&1; then
  pass "Jenkins job alchemy-rollback present"
else
  fail "Jenkins job alchemy-rollback missing (${NAME})"
  exit 1
fi

if remote "${IP}" "command -v npm >/dev/null && command -v node >/dev/null && node -v" >/dev/null 2>&1; then
  pass "Node.js/npm present for CI (${NAME})"
else
  fail "Node.js/npm missing on cicd (${NAME}) — required for lint/test/audit"
  exit 1
fi

exit 0
