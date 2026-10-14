#!/usr/bin/env bash
# Trigger a backup now from the host (runs backup-run on the backup VM).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant
require_guests_up

echo "========================================"
echo " Automation-VMs — backup now"
echo "========================================"

# Refresh exports on sources, then pull on backup
while IFS='|' read -r name ip; do
  [[ "${name}" == "backup" ]] && continue
  echo "==> Export on ${name}"
  guest_root "${name}" "install -m 755 /opt/automation-alchemy/scripts/aa-backup-apply-bundle.sh /usr/local/sbin/aa-backup-apply-bundle; /usr/local/sbin/aa-backup-export || true"
done < <(list_machines)

guest_root backup "install -m 755 /opt/automation-alchemy/scripts/backup-run.sh /usr/local/sbin/aa-backup-run; install -m 755 /opt/automation-alchemy/scripts/backup-restore.sh /usr/local/sbin/aa-backup-restore; install -m 755 /opt/automation-alchemy/scripts/backup-list.sh /usr/local/sbin/aa-backup-list; bash /opt/automation-alchemy/scripts/backup-run.sh"

echo "Done. Snapshots under /var/backups/automation-alchemy/weekly on backup VM."
echo "Verify:  make backup-list"
echo "         ssh -i keys/id_ed25519 devops@10.10.0.30 /usr/local/sbin/aa-backup-list"
echo "Restore: make backup-restore          # dry-run"
echo "         make backup-restore APPLY=1  # write files"
