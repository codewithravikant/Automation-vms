#!/bin/bash
# Create devops user, set a password, add to sudo (password required — no NOPASSWD).

set -euo pipefail

# Lab password for interactive sudo. SSH login remains key-only.
# Documented in docs/security.md and README.
DEVOPS_PASSWORD="${DEVOPS_PASSWORD:-devops}"

echo "==> Creating devops user"

if ! id devops >/dev/null 2>&1; then
  useradd -m -s /bin/bash devops
fi

usermod -aG sudo devops

# Ensure password is set so sudo prompts work (idempotent re-apply)
echo "devops:${DEVOPS_PASSWORD}" | chpasswd

# Remove any passwordless sudo drop-in from earlier provision runs
if [[ -f /etc/sudoers.d/devops ]]; then
  rm -f /etc/sudoers.d/devops
  echo "==> Removed /etc/sudoers.d/devops (NOPASSWD not allowed)"
fi

echo "==> devops ready (sudo requires password; groups: $(groups devops))"
