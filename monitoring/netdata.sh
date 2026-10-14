#!/bin/bash
# Stretch: install Netdata for live metrics (CPU, RAM, disk, network).
# Not required for Layer 1 marks. Not invoked by bootstrap.
# Set STRETCH_OPEN_UFW=1 to allow UI from the private lab network only.
#
# Prefer official static kickstart (HTTPS) — lab NAT often breaks apt HTTP :80
# even when ICMP to archive.ubuntu.com works. Fall back to Ubuntu apt.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (e.g. via provisioning or sudo)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
NETDATA_PORT="${NETDATA_PORT:-19999}"
LAB_CIDR="${LAB_CIDR:-10.10.0.0/24}"

wait_for_apt() {
  local i
  for i in $(seq 1 60); do
    if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
      && ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
      return 0
    fi
    echo "==> Waiting for apt lock (${i}/60)…"
    sleep 5
  done
  echo "Timed out waiting for apt lock" >&2
  return 1
}

# Static kickstart lands under /opt/netdata (binary often not on PATH).
netdata_installed() {
  command -v netdata >/dev/null 2>&1 && return 0
  [[ -x /opt/netdata/bin/netdata ]] && return 0
  [[ -x /opt/netdata/usr/sbin/netdata ]] && return 0
  [[ -x /opt/netdata/usr/bin/netdata ]] && return 0
  dpkg -s netdata >/dev/null 2>&1 && return 0
  systemctl cat netdata.service >/dev/null 2>&1 && return 0
  return 1
}

# HTTPS static binary — avoids flaky VirtualBox NAT → archive.ubuntu.com:80
install_via_kickstart_static() {
  echo "==> Installing Netdata via kickstart (static / HTTPS)"
  wait_for_apt || true
  curl -fsSL https://get.netdata.cloud/kickstart.sh -o /tmp/netdata-kickstart.sh
  sh /tmp/netdata-kickstart.sh \
    --stable-channel \
    --disable-telemetry \
    --dont-wait \
    --install-type static \
    --non-interactive
  local rc=$?
  rm -f /tmp/netdata-kickstart.sh
  if [[ "${rc}" -eq 0 ]] && netdata_installed; then
    return 0
  fi
  # Kickstart sometimes exits 0 after printing success; re-check paths
  if netdata_installed; then
    return 0
  fi
  return 1
}

install_via_apt() {
  echo "==> Trying Netdata from Ubuntu apt (HTTP mirrors)"
  wait_for_apt || return 1
  apt-get update -qq || return 1
  apt-cache show netdata >/dev/null 2>&1 || return 1
  apt-get install -y -qq netdata || return 1
  netdata_installed
}

if netdata_installed; then
  echo "Netdata already installed"
else
  if install_via_kickstart_static; then
    echo "==> Netdata installed (static)"
  elif install_via_apt; then
    echo "==> Netdata installed (apt)"
  else
    echo "Netdata install failed (HTTPS kickstart and apt both failed)." >&2
    echo "From the guest, check: curl -I https://get.netdata.cloud/" >&2
    echo "And HTTP mirrors: curl -I --connect-timeout 5 http://archive.ubuntu.com/ubuntu/" >&2
    exit 1
  fi
fi

systemctl enable netdata 2>/dev/null || true
systemctl restart netdata

if [[ "${STRETCH_OPEN_UFW:-0}" == "1" ]] && command -v ufw >/dev/null 2>&1; then
  echo "==> Allowing Netdata UI from lab network ${LAB_CIDR}"
  ufw allow from "${LAB_CIDR}" to any port "${NETDATA_PORT}" proto tcp comment 'automation-alchemy-netdata' || true
fi

HOST_IP="$(ip -4 -o addr show scope global 2>/dev/null | awk '/10\.10\.0\./ {print $4; exit}' | cut -d/ -f1)"
HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
echo "==> Netdata running on :${NETDATA_PORT}"
echo "    UI (from VirtualBox host / lab net): http://${HOST_IP:-<vm-ip>}:${NETDATA_PORT}"
if [[ "${STRETCH_OPEN_UFW:-0}" != "1" ]]; then
  echo "    UFW not opened. Re-run with STRETCH_OPEN_UFW=1 or:"
  echo "      sudo ufw allow from ${LAB_CIDR} to any port ${NETDATA_PORT} proto tcp"
fi
