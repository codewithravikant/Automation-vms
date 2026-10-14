#!/usr/bin/env bash
# Pull staged exports from lab hosts into dated weekly snapshots on the backup VM.
# Also usable from the Mac host via: make backup-now (SSHs to backup and runs this).

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/automation-alchemy}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${BACKUP_ROOT}/weekly/${STAMP}"
KEY="${PROJECT_ROOT}/keys/id_ed25519"
LOG="${BACKUP_ROOT}/logs/backup-${STAMP}.log"
SSH_OPTS=(-i "${KEY}" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts_ii -o BatchMode=yes -o ConnectTimeout=10)

HOSTS=(appserver web1 web2 loadbalancer)
FAILS=0

mkdir -p "${DEST}" "${BACKUP_ROOT}/logs" /root/.ssh
chmod 700 /root/.ssh

if [[ ! -f "${KEY}" ]]; then
  echo "Missing SSH key: ${KEY}" >&2
  exit 1
fi

# Prefer running as root on backup; if invoked as devops, use home known_hosts
if [[ "$(id -u)" -ne 0 ]]; then
  SSH_OPTS=(-i "${KEY}" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${HOME}/.ssh/known_hosts_ii" -o BatchMode=yes -o ConnectTimeout=10)
  mkdir -p "${HOME}/.ssh"
fi

exec > >(tee -a "${LOG}") 2>&1

echo "==> Automation-VMs backup ${STAMP}"

for host in "${HOSTS[@]}"; do
  echo "--> ${host}"
  mkdir -p "${DEST}/${host}"
  # Refresh remote export if possible (devops cannot sudo; export timer runs as root daily)
  ssh "${SSH_OPTS[@]}" "devops@${host}" \
    "test -f /var/lib/automation-alchemy/backup-export/latest.tar.gz" \
    || echo "WARN: ${host} has no staged export yet"

  if ! rsync -aH --numeric-ids \
    -e "ssh ${SSH_OPTS[*]}" \
    "devops@${host}:/var/lib/automation-alchemy/backup-export/latest.tar.gz" \
    "${DEST}/${host}/bundle.tar.gz"
  then
    echo "WARN: could not pull export from ${host}"
    FAILS=$((FAILS + 1))
  fi

  # Always copy devops home as a live tree (easy restore)
  mkdir -p "${DEST}/${host}/home-devops"
  if ! rsync -aH --delete --numeric-ids \
    -e "ssh ${SSH_OPTS[*]}" \
    "devops@${host}:/home/devops/" \
    "${DEST}/${host}/home-devops/"
  then
    echo "WARN: home rsync failed for ${host}"
    FAILS=$((FAILS + 1))
  fi
done

# devops group can list/read snapshots; tighten private keys inside homes
chown -R root:devops "${DEST}"
chmod -R g+rX "${DEST}"
find "${DEST}" -type d -name '.ssh' -exec chmod 700 {} \; 2>/dev/null || true
find "${DEST}" -path '*/.ssh/*' -type f -exec chmod 600 {} \; 2>/dev/null || true

chown root:devops "${BACKUP_ROOT}" "${BACKUP_ROOT}/weekly" "${BACKUP_ROOT}/logs"
chmod 750 "${BACKUP_ROOT}" "${BACKUP_ROOT}/weekly" "${BACKUP_ROOT}/logs"

echo "==> Pruning old weekly backups (keep 4)"
ls -1dt "${BACKUP_ROOT}/weekly"/*/ 2>/dev/null | tail -n +5 | while read -r old; do
  rm -rf "${old}"
done

ln -sfn "${DEST}" "${BACKUP_ROOT}/weekly/latest"
chown -h root:devops "${BACKUP_ROOT}/weekly/latest" 2>/dev/null || true

echo "==> Backup complete: ${DEST}"
echo "    List snapshots: /usr/local/sbin/aa-backup-list (or: make backup-list)"

if [[ "${FAILS}" -gt 0 ]]; then
  echo "ERROR: ${FAILS} host pull(s) failed" >&2
  exit 1
fi
