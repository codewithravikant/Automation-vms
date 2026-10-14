#!/usr/bin/env bash
# Pretty reviewer-friendly wrapper around verify / tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

TMP_OUT="$(mktemp)"
trap 'rm -f "${TMP_OUT}"' EXIT

bold ""
bold "╔══════════════════════════════════════════╗"
bold "║       AUTOMATION ALCHEMY REVIEW              ║"
bold "╚══════════════════════════════════════════╝"
echo ""
echo "Running automated checklist against all VMs..."
echo "Tests: hostname, static IP, SSH, firewall, users, umask, updates"
echo ""

set +e
"${SCRIPT_DIR}/verify.sh" 2>&1 | tee "${TMP_OUT}"
rc=${PIPESTATUS[0]}
set -e

echo ""
bold "──────────────────────────────────────────"

if [[ "${rc}" -eq 0 ]]; then
  green "✔ REVIEW RESULT: PASSED"
  echo ""
  echo "Reviewers can also SSH manually:"
  while IFS='|' read -r name ip; do
    echo "  ssh -i keys/id_ed25519 devops@${ip}  # ${name}"
  done < <(list_machines)
  echo ""
  echo "Interactive sudo password for devops: devops"
  echo "(SSH login remains key-only.)"
  exit 0
fi

red "✘ REVIEW RESULT: FAILED"
echo ""
echo "See failures above. Common fixes: make reset && make verify"
echo "Docs: docs/troubleshooting.md"
exit 1
