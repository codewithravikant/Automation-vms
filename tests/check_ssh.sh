#!/usr/bin/env bash
# Check: SSH hardening — key login, no root, no password auth, AllowUsers devops.
# Usage: check_ssh.sh <name> <ip>
# Does not use sudo (works without NOPASSWD).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

ok=1

if remote "${IP}" "true" >/dev/null 2>&1; then
  pass "ssh key login (${NAME})"
else
  fail "ssh key login (${NAME})"
  ok=0
fi

# Root login must fail
if ssh -i "${PRIVATE_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    -o BatchMode=yes \
    -o PreferredAuthentications=publickey \
    "root@${IP}" "true" >/dev/null 2>&1; then
  fail "root SSH disabled (${NAME})"
  ok=0
else
  pass "root SSH disabled (${NAME})"
fi

# Read drop-in without sudo
dropin="$(remote "${IP}" "cat /etc/ssh/sshd_config.d/99-automation-alchemy.conf" 2>/dev/null || true)"

if echo "${dropin}" | grep -Eqi '^[[:space:]]*PasswordAuthentication[[:space:]]+no'; then
  pass "password auth disabled (${NAME})"
else
  fail "password auth disabled (${NAME})"
  ok=0
fi

if echo "${dropin}" | grep -Eqi '^[[:space:]]*PermitRootLogin[[:space:]]+no'; then
  pass "PermitRootLogin no (${NAME})"
else
  fail "PermitRootLogin no (${NAME})"
  ok=0
fi

# Global AllowUsers must be devops-only (vagrant only via Match NAT block)
if echo "${dropin}" | grep -Eqi '^[[:space:]]*AllowUsers[[:space:]]+devops[[:space:]]*$'; then
  pass "AllowUsers devops (${NAME})"
else
  fail "AllowUsers devops (${NAME})"
  ok=0
fi

if [[ "${ok}" -eq 1 ]]; then
  exit 0
fi
exit 1
