#!/usr/bin/env bash
# Check: hostname matches expected machine name.
# Usage: check_hostname.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

out="$(remote "${IP}" "hostname" 2>/dev/null || true)"
if [[ "${out}" == "${NAME}" ]]; then
  pass "hostname (${NAME})"
  exit 0
fi
fail "hostname (expected ${NAME}, got: ${out:-ssh failed})"
exit 1
