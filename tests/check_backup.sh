#!/usr/bin/env bash
# Check: backup VM weekly timer + restore tools; export hosts stage + apply helpers.
# Usage: check_backup.sh <name> <ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

ok=1

if [[ "${NAME}" == "backup" ]]; then
  if remote "${IP}" "test -x /usr/local/sbin/aa-backup-run" >/dev/null 2>&1; then
    pass "backup-run installed (${NAME})"
  else
    fail "backup-run installed (${NAME})"
    ok=0
  fi

  if remote "${IP}" "test -x /usr/local/sbin/aa-backup-restore" >/dev/null 2>&1; then
    pass "backup-restore installed (${NAME})"
  else
    fail "backup-restore installed (${NAME})"
    ok=0
  fi

  if remote "${IP}" "systemctl is-enabled aa-backup.timer" >/dev/null 2>&1; then
    pass "backup timer enabled (${NAME})"
  else
    fail "backup timer enabled (${NAME})"
    ok=0
  fi

  # devops must be able to list weekly stamps (group perms) or run aa-backup-list
  if remote "${IP}" "test -x /usr/local/sbin/aa-backup-list && /usr/local/sbin/aa-backup-list >/dev/null" >/dev/null 2>&1 \
    || remote "${IP}" "test -r /var/backups/automation-alchemy/weekly && ls /var/backups/automation-alchemy/weekly >/dev/null" >/dev/null 2>&1; then
    pass "backup list readable by devops (${NAME})"
  else
    fail "backup list readable by devops (${NAME})"
    ok=0
  fi

  [[ "${ok}" -eq 1 ]]
  exit 0
fi

# Export hosts: appserver, web1, web2, loadbalancer
case "${NAME}" in
  appserver|web1|web2|loadbalancer) ;;
  *)
    pass "backup check N/A (${NAME})"
    exit 0
    ;;
esac

if remote "${IP}" "test -x /usr/local/sbin/aa-backup-export" >/dev/null 2>&1; then
  pass "backup-export installed (${NAME})"
else
  fail "backup-export installed (${NAME})"
  ok=0
fi

if remote "${IP}" "test -x /usr/local/sbin/aa-backup-apply-bundle" >/dev/null 2>&1; then
  pass "backup-apply-bundle installed (${NAME})"
else
  fail "backup-apply-bundle installed (${NAME})"
  ok=0
fi

if remote "${IP}" "systemctl is-enabled aa-backup-export.timer" >/dev/null 2>&1; then
  pass "backup-export timer enabled (${NAME})"
else
  fail "backup-export timer enabled (${NAME})"
  ok=0
fi

[[ "${ok}" -eq 1 ]]
