#!/usr/bin/env bash
# Check: secure umask 027 / 0027 on a login shell.
# Usage: check_umask.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

out="$(remote "${IP}" "bash -lc 'umask'" 2>/dev/null || true)"
if echo "${out}" | grep -Eq '0?027'; then
  pass "umask (${NAME}: ${out})"
  exit 0
fi
fail "umask (${NAME}: got ${out:-ssh failed})"
exit 1
