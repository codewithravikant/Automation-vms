#!/usr/bin/env bash
# Install aa-backup-list on backup VM, fix group perms, then list as devops.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

require_vagrant
require_guests_up

echo "========================================"
echo " Automation-VMs — backup list"
echo "========================================"

guest_root backup 'install -m 755 /opt/automation-alchemy/scripts/backup-list.sh /usr/local/sbin/aa-backup-list; mkdir -p /var/backups/automation-alchemy/weekly /var/backups/automation-alchemy/logs; chown root:devops /var/backups/automation-alchemy /var/backups/automation-alchemy/weekly /var/backups/automation-alchemy/logs; chmod 750 /var/backups/automation-alchemy /var/backups/automation-alchemy/weekly /var/backups/automation-alchemy/logs; chown -R root:devops /var/backups/automation-alchemy/weekly 2>/dev/null || true; chmod -R g+rX /var/backups/automation-alchemy/weekly 2>/dev/null || true; find /var/backups/automation-alchemy/weekly -type d -name .ssh -exec chmod 700 {} \; 2>/dev/null || true; find /var/backups/automation-alchemy/weekly -path "*/.ssh/*" -type f -exec chmod 600 {} \; 2>/dev/null || true'

ssh_devops 10.10.0.30 '/usr/local/sbin/aa-backup-list'
