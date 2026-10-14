#!/bin/bash
# Set a secure default umask (027 / 0027) from config/ templates.

set -euo pipefail

ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
PROFILE_SRC="${ROOT}/config/zz-secure-umask.sh"
LOGIN_DEFS_SRC="${ROOT}/config/login.defs.umask"
PROFILE_SNIPPET=/etc/profile.d/zz-secure-umask.sh

echo "==> Setting secure umask 027"

if [[ -f "${PROFILE_SRC}" ]]; then
  cp "${PROFILE_SRC}" "${PROFILE_SNIPPET}"
else
  cat >"${PROFILE_SNIPPET}" <<'EOF'
# Automation-VMs — secure default umask
umask 027
EOF
fi
chmod 644 "${PROFILE_SNIPPET}"

# Apply UMASK in login.defs (idempotent replace or append)
UMASK_VALUE="027"
if [[ -f "${LOGIN_DEFS_SRC}" ]]; then
  # shellcheck disable=SC2002
  UMASK_VALUE="$(grep -E '^UMASK' "${LOGIN_DEFS_SRC}" | awk '{print $2}' | head -1)"
  UMASK_VALUE="${UMASK_VALUE:-027}"
fi

if grep -qE '^UMASK' /etc/login.defs; then
  sed -i "s/^UMASK.*/UMASK\t\t${UMASK_VALUE}/" /etc/login.defs
else
  echo -e "UMASK\t\t${UMASK_VALUE}" >> /etc/login.defs
fi

# devops bashrc for non-login interactive shells (idempotent)
if id devops >/dev/null 2>&1; then
  BASHRC=/home/devops/.bashrc
  if [[ -f "${BASHRC}" ]] && ! grep -qE '^[[:space:]]*umask[[:space:]]+027' "${BASHRC}"; then
    echo 'umask 027' >> "${BASHRC}"
  fi
fi

echo "==> umask configured"
