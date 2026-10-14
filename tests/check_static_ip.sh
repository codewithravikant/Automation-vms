#!/usr/bin/env bash
# Check: static private IP is present on the guest.
# Usage: check_static_ip.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

out="$(remote "${IP}" "ip -4 -o addr show" 2>/dev/null || true)"
if echo "${out}" | grep -Fq "${IP}"; then
  pass "static IP (${NAME} ${IP})"
  exit 0
fi
fail "static IP (${NAME} ${IP})"
exit 1
