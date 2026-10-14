#!/usr/bin/env bash
# Orchestrate tests/ against every VM. Exit 0 only if all checks pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

TESTS_DIR="${ROOT}/tests"
PASS_COUNT=0
FAIL_COUNT=0

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }

CHECKS=(
  check_hostname.sh
  check_static_ip.sh
  check_ssh.sh
  check_firewall.sh
  check_users.sh
  check_umask.sh
  check_updates.sh
  check_docker.sh
  check_app.sh
  check_backup.sh
  check_cicd.sh
)

run_check() {
  local script="$1"
  local name="$2"
  local ip="$3"
  local path="${TESTS_DIR}/${script}"
  local out rc=0

  if [[ ! -x "${path}" && ! -f "${path}" ]]; then
    red "  ✗ missing test: ${script}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  set +e
  out="$(bash "${path}" "${name}" "${ip}" 2>&1)"
  rc=$?
  set -e

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    if [[ "${line}" == PASS* ]]; then
      green "  ✓ ${line#PASS }"
      PASS_COUNT=$((PASS_COUNT + 1))
    elif [[ "${line}" == FAIL* ]]; then
      red "  ✗ ${line#FAIL }"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      printf '  %s\n' "${line}"
    fi
  done <<< "${out}"

  # If script failed but printed no FAIL lines, count one failure
  if [[ "${rc}" -ne 0 ]] && ! echo "${out}" | grep -q '^FAIL'; then
    red "  ✗ ${script} exited ${rc}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

ensure_ssh_key

echo "========================================"
echo " Automation-VMs — verify"
echo "========================================"

if [[ ! -f "${PRIVATE_KEY}" ]]; then
  echo "Missing project key. Run ./scripts/create.sh first." >&2
  exit 1
fi

while IFS='|' read -r name ip; do
  echo ""
  echo "── ${name} (${ip}) ──"

  if ! ping -c 1 -W 3 "${ip}" >/dev/null 2>&1; then
    red "  ✗ reachable via ping"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    for script in "${CHECKS[@]}"; do
      red "  ✗ skipped ${script} (host unreachable)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    done
    continue
  fi
  green "  ✓ reachable via ping"
  PASS_COUNT=$((PASS_COUNT + 1))

  for script in "${CHECKS[@]}"; do
    run_check "${script}" "${name}" "${ip}"
  done
done < <(list_machines)

echo ""
echo "========================================"
echo " Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi

echo "All review checks passed."
exit 0
