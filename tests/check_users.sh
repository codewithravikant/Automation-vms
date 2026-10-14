#!/usr/bin/env bash
# Check: devops exists, in sudo, and sudo requires a password (no NOPASSWD).
# Usage: check_users.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

ok=1

user="$(remote "${IP}" "id -un devops" 2>/dev/null || true)"
if [[ "${user}" == "devops" ]]; then
  pass "devops exists (${NAME})"
else
  fail "devops exists (${NAME})"
  ok=0
fi

groups_out="$(remote "${IP}" "groups devops" 2>/dev/null || true)"
if echo "${groups_out}" | grep -Eq '\bsudo\b'; then
  pass "devops in sudo (${NAME})"
else
  fail "devops in sudo (${NAME})"
  ok=0
fi

# sudo -n must fail when password is required and NOPASSWD is absent
if remote "${IP}" "sudo -n true" >/dev/null 2>&1; then
  fail "sudo requires password (${NAME}) — NOPASSWD still active"
  ok=0
else
  pass "sudo requires password (${NAME})"
fi

# Ensure no devops NOPASSWD drop-in
if remote "${IP}" "test -f /etc/sudoers.d/devops" >/dev/null 2>&1; then
  fail "no /etc/sudoers.d/devops NOPASSWD (${NAME})"
  ok=0
else
  pass "no NOPASSWD drop-in (${NAME})"
fi

if [[ "${ok}" -eq 1 ]]; then
  exit 0
fi
exit 1
