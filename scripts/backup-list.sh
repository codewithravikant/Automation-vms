#!/usr/bin/env bash
# List weekly backup stamps on the backup VM (readable by devops via group perms).
# Installed as /usr/local/sbin/aa-backup-list

# Intentionally no set -e: find on unreadable .ssh must not abort listing.

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/automation-alchemy}"
WEEKLY="${BACKUP_ROOT}/weekly"

echo "==> Automation-VMs backups under ${WEEKLY}"

if [[ ! -d "${WEEKLY}" ]]; then
  echo "No weekly directory: ${WEEKLY}"
  echo "(Permission denied? Ask root to: chown root:devops ${BACKUP_ROOT} && chmod 750 ${BACKUP_ROOT})"
  exit 1
fi

if [[ -L "${WEEKLY}/latest" ]]; then
  target="$(readlink "${WEEKLY}/latest" 2>/dev/null || true)"
  echo "latest -> ${target}"
elif [[ -e "${WEEKLY}/latest" ]]; then
  echo "latest: $(ls -ld "${WEEKLY}/latest" 2>/dev/null || true)"
else
  echo "latest: (none)"
fi

echo ""
shopt -s nullglob
stamps=("${WEEKLY}"/*/)
if [[ ${#stamps[@]} -eq 0 ]]; then
  echo "(no stamp directories yet — run: make backup-now)"
  exit 0
fi

# Newest first
IFS=$'\n' sorted=($(ls -1dt "${WEEKLY}"/*/ 2>/dev/null)) || sorted=()
unset IFS

for stamp_dir in "${sorted[@]}"; do
  stamp="$(basename "${stamp_dir%/}")"
  [[ "${stamp}" == "latest" ]] && continue
  echo "--- ${stamp} ---"
  for host_dir in "${stamp_dir}"*/; do
    [[ -d "${host_dir}" ]] || continue
    host="$(basename "${host_dir%/}")"
    bundle="${host_dir}bundle.tar.gz"
    home="${host_dir}home-devops"
    size="-"
    [[ -f "${bundle}" ]] && size="$(du -h "${bundle}" 2>/dev/null | awk '{print $1}')"
    count="?"
    if [[ -d "${home}" ]]; then
      # Tolerate permission errors on .ssh (group may lack execute on 700 dirs)
      count="$(find "${home}" -type f 2>/dev/null | wc -l | tr -d ' ')" || count="?"
    fi
    echo "  ${host}: bundle=${size}  home-devops files=${count}"
  done
done
