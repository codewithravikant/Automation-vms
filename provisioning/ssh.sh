#!/bin/bash
# Install OpenSSH, apply hardened sshd drop-in from config/, inject devops key.

set -euo pipefail

ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
SSHD_TEMPLATE="${ROOT}/config/sshd_config"
# Fallback for older trees that still ship under security/
if [[ ! -f "${SSHD_TEMPLATE}" && -f "${ROOT}/security/sshd_config" ]]; then
  SSHD_TEMPLATE="${ROOT}/security/sshd_config"
fi
SSHD_DROPIN="/etc/ssh/sshd_config.d/99-automation-alchemy.conf"

echo "==> Installing OpenSSH server"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq openssh-server

echo "==> Applying SSH hardening"
mkdir -p /etc/ssh/sshd_config.d
if [[ -f "${SSHD_TEMPLATE}" ]]; then
  cp "${SSHD_TEMPLATE}" "${SSHD_DROPIN}"
else
  cat >"${SSHD_DROPIN}" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
AllowUsers devops

Match Address 10.0.2.0/24
	AllowUsers devops vagrant
EOF
fi
chmod 644 "${SSHD_DROPIN}"

# Neutralize conflicting defaults in cloud image snippets if present
for conf in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [[ -f "${conf}" ]] || continue
  [[ "${conf}" == "${SSHD_DROPIN}" ]] && continue
  sed -i 's/^[#[:space:]]*PasswordAuthentication.*/# PasswordAuthentication overridden by 99-automation-alchemy/' "${conf}" || true
  sed -i 's/^[#[:space:]]*PermitRootLogin.*/# PermitRootLogin overridden by 99-automation-alchemy/' "${conf}" || true
done

mkdir -p /home/devops/.ssh
chmod 700 /home/devops/.ssh

if [[ -f /tmp/devops_authorized_key ]]; then
  cat /tmp/devops_authorized_key > /home/devops/.ssh/authorized_keys
  chmod 600 /home/devops/.ssh/authorized_keys
  chown -R devops:devops /home/devops/.ssh
  rm -f /tmp/devops_authorized_key
  echo "==> devops authorized_keys installed"
else
  echo "==> WARNING: no devops pubkey at /tmp/devops_authorized_key"
fi

sshd -t
systemctl enable ssh
systemctl restart ssh

echo "==> SSH hardened"
