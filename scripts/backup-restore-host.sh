#!/usr/bin/env bash
# Dry-run or apply restore via the backup VM, then apply staged bundles on export hosts.
#
# Usage:
#   ./scripts/backup-restore-host.sh [--apply] [--with-etc]
# Env: APPLY=1, WITH_ETC=1 (also accepted via Make)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant

APPLY_FLAG=""
WITH_ETC_FLAG=""
APPLY_MODE="--dry-run"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY_FLAG="--apply"; APPLY_MODE="--apply"; shift ;;
    --with-etc) WITH_ETC_FLAG="--with-etc"; shift ;;
    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "${APPLY:-}" == "1" ]]; then
  APPLY_FLAG="--apply"
  APPLY_MODE="--apply"
fi
if [[ "${WITH_ETC:-}" == "1" ]]; then
  WITH_ETC_FLAG="--with-etc"
fi

echo "========================================"
echo " Automation-VMs — backup restore ${APPLY_FLAG:-dry-run}${WITH_ETC_FLAG:+ ${WITH_ETC_FLAG}}"
echo "========================================"

if [[ -z "${APPLY_FLAG}" ]]; then
  echo "NOTE: dry-run does not write files. To restore for real: make backup-restore APPLY=1"
fi

# Refresh restore runner on backup, then homes + stage bundles
guest_root backup "install -m 755 /opt/automation-alchemy/scripts/backup-restore.sh /usr/local/sbin/aa-backup-restore; bash /opt/automation-alchemy/scripts/backup-restore.sh ${APPLY_FLAG} ${WITH_ETC_FLAG}"

STAGE_ROOT="${ROOT}/.restore-staging"
EXPORT_HOSTS=(appserver web1 web2 loadbalancer)

# 2) Apply (or dry-run) bundles on each export host as root via vagrant
for host in "${EXPORT_HOSTS[@]}"; do
  bundle="${STAGE_ROOT}/${host}/bundle.tar.gz"
  if [[ ! -f "${bundle}" ]]; then
    echo "--> ${host}: no staged bundle, skip"
    continue
  fi
  echo "--> ${host}: install apply helper + ${APPLY_MODE} bundle"
  guest_root "${host}" "install -m 755 /opt/automation-alchemy/scripts/aa-backup-apply-bundle.sh /usr/local/sbin/aa-backup-apply-bundle && /usr/local/sbin/aa-backup-apply-bundle ${APPLY_MODE} ${WITH_ETC_FLAG} /opt/automation-alchemy/.restore-staging/${host}/bundle.tar.gz"
done

if [[ -n "${APPLY_FLAG}" ]]; then
  echo "==> APPLY finished"
else
  echo "==> DRY-RUN finished — use APPLY=1 to write files"
fi
