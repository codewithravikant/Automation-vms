#!/bin/bash
# On application/web/lb hosts: stage a root-readable export for the backup VM to pull.
# Skips the backup host itself.

set -euo pipefail

HOST_NAME="${VM_HOSTNAME:-$(hostname -s)}"
case "${HOST_NAME}" in
  backup)
    echo "==> Skipping backup-export on backup host"
    exit 0
    ;;
esac

EXPORT_DIR="/var/lib/automation-alchemy/backup-export"
mkdir -p "${EXPORT_DIR}" /var/lib/automation-alchemy
chown devops:devops /var/lib/automation-alchemy || true

cat >/usr/local/sbin/aa-backup-export <<'EOF'
#!/bin/bash
set -euo pipefail
EXPORT_DIR="/var/lib/automation-alchemy/backup-export"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TMP="${EXPORT_DIR}/.staging-${STAMP}"
OUT="${EXPORT_DIR}/latest.tar.gz"
ERR="${EXPORT_DIR}/.last-export.err"
mkdir -p "${TMP}"
rm -f "${ERR}"

# --exclude must come BEFORE member paths (GNU tar)
set +e
tar -C / -czf "${TMP}/bundle.tar.gz" \
  --exclude=var/lib/automation-alchemy/backup-export \
  home/devops \
  etc \
  var/lib/automation-alchemy \
  2>"${ERR}"
tar_rc=$?
set -e

if [[ ${tar_rc} -ne 0 || ! -s "${TMP}/bundle.tar.gz" ]]; then
  echo "WARN: full export failed (rc=${tar_rc}); falling back to home/devops + etc" >&2
  [[ -s "${ERR}" ]] && cat "${ERR}" >&2 || true
  set +e
  tar -C / -czf "${TMP}/bundle.tar.gz" home/devops etc 2>"${ERR}"
  tar_rc=$?
  set -e
  if [[ ${tar_rc} -ne 0 || ! -s "${TMP}/bundle.tar.gz" ]]; then
    echo "ERROR: fallback export also failed (rc=${tar_rc})" >&2
    [[ -s "${ERR}" ]] && cat "${ERR}" >&2 || true
    rm -rf "${TMP}"
    exit 1
  fi
fi

mv -f "${TMP}/bundle.tar.gz" "${OUT}"
rm -rf "${TMP}"
chmod 644 "${OUT}"
echo "Export ready: ${OUT} ($(du -h "${OUT}" | awk '{print $1}'))"
EOF
chmod 755 /usr/local/sbin/aa-backup-export

# Restore helper: extract allowed prefixes from a staged bundle as root
ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
if [[ -f "${ROOT}/scripts/aa-backup-apply-bundle.sh" ]]; then
  install -m 755 "${ROOT}/scripts/aa-backup-apply-bundle.sh" /usr/local/sbin/aa-backup-apply-bundle
else
  echo "WARN: ${ROOT}/scripts/aa-backup-apply-bundle.sh missing — skip install"
fi

cat >/etc/systemd/system/aa-backup-export.service <<'EOF'
[Unit]
Description=Stage Automation-VMs backup export
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aa-backup-export
EOF

cat >/etc/systemd/system/aa-backup-export.timer <<'EOF'
[Unit]
Description=Daily backup export staging
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable aa-backup-export.timer
systemctl start aa-backup-export.timer
/usr/local/sbin/aa-backup-export || true

echo "==> Backup export staging enabled on ${HOST_NAME}"
