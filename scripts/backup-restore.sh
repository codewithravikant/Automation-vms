#!/usr/bin/env bash
# Restore from a weekly snapshot on the backup VM.
# Homes: rsync live home-devops trees.
# Bundles: stage into the synced project tree for host-side apply-bundle
# (app data + optional /etc via aa-backup-apply-bundle on each export host).
#
# Usage:
#   aa-backup-restore [--apply] [--with-etc] [/path/to/stamp]

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/automation-alchemy}"
KEY="${PROJECT_ROOT}/keys/id_ed25519"
SSH_OPTS=(-i "${KEY}" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts_ii -o BatchMode=yes -o ConnectTimeout=10)
STAGE_ROOT="${PROJECT_ROOT}/.restore-staging"

APPLY=0
WITH_ETC=0
SRC="${BACKUP_ROOT}/weekly/latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --with-etc) WITH_ETC=1; shift ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      SRC="$1"
      shift
      ;;
  esac
done

if [[ -L "${SRC}" ]]; then
  SRC="$(readlink -f "${SRC}")"
fi

if [[ ! -d "${SRC}" ]]; then
  echo "Snapshot not found: ${SRC}" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  SSH_OPTS=(-i "${KEY}" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${HOME}/.ssh/known_hosts_ii" -o BatchMode=yes -o ConnectTimeout=10)
fi

echo "==> Restore source: ${SRC}"
echo "==> Mode: $([[ ${APPLY} -eq 1 ]] && echo APPLY || echo DRY-RUN)$([[ ${WITH_ETC} -eq 1 ]] && echo ' (WITH_ETC requested for host apply)' || true)"

rm -rf "${STAGE_ROOT}"
mkdir -p "${STAGE_ROOT}"

for host in appserver web1 web2 loadbalancer; do
  home_src="${SRC}/${host}/home-devops/"
  if [[ -d "${home_src}" ]]; then
    flags=(-aH --numeric-ids)
    [[ "${APPLY}" -eq 1 ]] || flags+=(--dry-run -i)
    if [[ "${APPLY}" -eq 1 ]]; then
      echo "--> ${host}:/home/devops/ (APPLY live tree)"
    else
      echo "--> ${host}:/home/devops/ (DRY-RUN live tree)"
    fi
    rsync "${flags[@]}" -e "ssh ${SSH_OPTS[*]}" "${home_src}" "devops@${host}:/home/devops/"
  fi

  bundle="${SRC}/${host}/bundle.tar.gz"
  if [[ -f "${bundle}" ]]; then
    mkdir -p "${STAGE_ROOT}/${host}"
    cp -f "${bundle}" "${STAGE_ROOT}/${host}/bundle.tar.gz"
    echo "--> ${host}: staged bundle at ${STAGE_ROOT}/${host}/bundle.tar.gz"
    echo "    prefixes: home/devops, var/lib/automation-alchemy$([[ ${WITH_ETC} -eq 1 ]] && echo ', etc' || echo ' (etc opt-in via WITH_ETC=1)')"
    tar -tzf "${bundle}" 2>/dev/null | grep -E '^(home/devops|var/lib/automation-alchemy|etc)' | head -n 15 || true
  else
    echo "--> ${host}: no bundle.tar.gz"
  fi
done

# Marker for host wrapper
{
  echo "SRC=${SRC}"
  echo "APPLY=${APPLY}"
  echo "WITH_ETC=${WITH_ETC}"
  echo "STAGED_AT=$(date -u +%Y%m%dT%H%M%SZ)"
} >"${STAGE_ROOT}/meta.env"

if [[ "${APPLY}" -eq 1 ]]; then
  echo "==> Homes + staging finished (host wrapper applies bundles next)"
else
  echo "==> DRY-RUN: nothing was written to remote homes"
  echo "    To apply: make backup-restore APPLY=1"
  echo "==> Homes + staging finished (host wrapper applies bundles next)"
fi
