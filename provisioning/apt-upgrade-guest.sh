#!/bin/bash
# Root on one guest: HTTPS mirrors, then apt update && apt upgrade.
# HOLD_JENKINS=1 skips the jenkins package (a running build must not restart it).

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/apt-https.sh"

mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
if (( mem_mb < 1500 )) && ! swapon --show | grep -q '/swapfile'; then
  echo "==> Adding 1G swap (${mem_mb}MB RAM)"
  if [[ ! -f /swapfile ]]; then
    fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
  fi
  swapon /swapfile || true
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

if [[ "${HOLD_JENKINS:-}" == "1" ]]; then
  apt-mark hold jenkins || true
fi

ok=0
for attempt in 1 2 3; do
  if apt-get update -qq && apt-get -y -qq \
      -o APT::Get::Always-Include-Phased-Updates=true \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      -o DPkg::Lock::Timeout=300 \
      upgrade --fix-missing; then
    ok=1
    break
  fi
  echo "==> apt failed (attempt ${attempt}/3); retrying in 20s"
  sleep 20
done

if [[ "${HOLD_JENKINS:-}" == "1" ]]; then
  apt-mark unhold jenkins || true
fi

if [[ "${ok}" != "1" ]]; then
  echo "apt upgrade failed on $(hostname)" >&2
  exit 1
fi

echo "==> Still upgradable on $(hostname):"
left="$(apt list --upgradable 2>/dev/null | awk '!/^Listing/ && NF {print}')"
if [[ -z "${left}" ]]; then
  echo "(none)"
else
  printf '%s\n' "${left}"
fi
