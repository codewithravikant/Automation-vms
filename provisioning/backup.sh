#!/bin/bash
# Configure backup VM: destination dirs, rsync tooling, weekly timer.
# Only intended for VM_HOSTNAME=backup.

set -euo pipefail

ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
BACKUP_ROOT="/var/backups/automation-alchemy"

echo "==> Configuring backup host"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq rsync

mkdir -p "${BACKUP_ROOT}/weekly" "${BACKUP_ROOT}/logs"
chown root:devops "${BACKUP_ROOT}" "${BACKUP_ROOT}/weekly" "${BACKUP_ROOT}/logs"
chmod 750 "${BACKUP_ROOT}" "${BACKUP_ROOT}/weekly" "${BACKUP_ROOT}/logs"

# Install backup runner (pulls from appserver / web hosts over SSH as devops)
install -m 755 "${ROOT}/scripts/backup-run.sh" /usr/local/sbin/aa-backup-run
install -m 755 "${ROOT}/scripts/backup-restore.sh" /usr/local/sbin/aa-backup-restore
install -m 755 "${ROOT}/scripts/backup-list.sh" /usr/local/sbin/aa-backup-list

# Weekly full backup — Sundays 02:30 local
cat >/etc/systemd/system/aa-backup.service <<'EOF'
[Unit]
Description=Automation-VMs weekly backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aa-backup-run
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

cat >/etc/systemd/system/aa-backup.timer <<'EOF'
[Unit]
Description=Weekly Automation-VMs backup timer

[Timer]
OnCalendar=Sun *-*-* 02:30:00
Persistent=true
Unit=aa-backup.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable aa-backup.timer
systemctl start aa-backup.timer

echo "==> Backup timer enabled (weekly Sunday 02:30)"
systemctl list-timers aa-backup.timer --no-pager || true
