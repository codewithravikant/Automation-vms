#!/usr/bin/env bash
# Check: unattended-upgrades enabled and 20auto-upgrades present.
# Usage: check_updates.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

ok=1

enabled="$(remote "${IP}" "systemctl is-enabled unattended-upgrades" 2>/dev/null || true)"
if [[ "${enabled}" == "enabled" ]]; then
  pass "unattended-upgrades enabled (${NAME})"
else
  fail "unattended-upgrades enabled (${NAME}: ${enabled})"
  ok=0
fi

cfg="$(remote "${IP}" "cat /etc/apt/apt.conf.d/20auto-upgrades" 2>/dev/null || true)"
if echo "${cfg}" | grep -Fq 'Unattended-Upgrade'; then
  pass "20auto-upgrades present (${NAME})"
else
  fail "20auto-upgrades present (${NAME})"
  ok=0
fi

if [[ "${ok}" -eq 1 ]]; then
  exit 0
fi
exit 1
