#!/usr/bin/env bash
# Preflight: verify this host can create Automation-VMs lab VMs.
# Exit 0 = capable; exit 1 = not capable (prints clear failure).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

FAILED=0
REASONS=()

fail() {
  FAILED=1
  REASONS+=("$1")
}

ok() {
  echo "  [OK] $1"
}

warn() {
  echo "  [WARN] $1"
}

# Guest RAM from machines.yml (MB), plus host overhead.
required_guest_mb() {
  awk '
    /^[[:space:]]*memory:[[:space:]]*[0-9]+/ {
      sum += $2
    }
    END { print sum + 0 }
  ' "${MACHINES_YML}"
}

available_ram_mb() {
  local os
  os="$(uname -s)"
  case "${os}" in
    Linux)
      # awk exit still runs END — use one print path only
      awk '
        /MemAvailable:/ { avail = int($2 / 1024); found = 1; next }
        /MemFree:/ { free = $2 }
        /Buffers:/ { buffers = $2 }
        /^Cached:/ { cached = $2 }
        END {
          if (found) { print avail; exit }
          if (free + buffers + cached > 0)
            print int((free + buffers + cached) / 1024)
          else
            print 0
        }' /proc/meminfo
      ;;
    Darwin)
      # Pages free + inactive (approx available)
      local page_size free inactive speculative
      page_size="$(pagesize 2>/dev/null || sysctl -n hw.pagesize)"
      free="$(vm_stat | awk '/Pages free/ { gsub(/\./,"",$3); print $3 }')"
      inactive="$(vm_stat | awk '/Pages inactive/ { gsub(/\./,"",$3); print $3 }')"
      speculative="$(vm_stat | awk '/Pages speculative/ { gsub(/\./,"",$3); print $3 }')"
      echo $(( (free + inactive + speculative) * page_size / 1024 / 1024 ))
      ;;
    *)
      echo "0"
      ;;
  esac
}

total_ram_mb() {
  local os
  os="$(uname -s)"
  case "${os}" in
    Linux)
      awk '/MemTotal:/ { print int($2 / 1024); exit }' /proc/meminfo
      ;;
    Darwin)
      echo $(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
      ;;
    *)
      echo "0"
      ;;
  esac
}

disk_free_gb() {
  df -Pk / 2>/dev/null | awk 'NR==2 { print int($4 / 1024 / 1024) }'
}

has_cpu_virt() {
  local os
  os="$(uname -s)"
  case "${os}" in
    Linux)
      if [[ -r /proc/cpuinfo ]] && grep -Eiq '(vmx|svm)' /proc/cpuinfo; then
        return 0
      fi
      return 1
      ;;
    Darwin)
      # Intel Macs report VMX; Apple Silicon is caught by arch check.
      if sysctl -n machdep.cpu.features 2>/dev/null | grep -Eqi 'VMX'; then
        return 0
      fi
      # If VirtualBox is installed on Intel/Apple and reports a host, accept.
      if command -v VBoxManage >/dev/null 2>&1; then
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

echo "========================================"
echo " Automation-VMs — host safety check"
echo "========================================"
echo ""

# --- Architecture (ubuntu/jammy64 is x86_64) ---
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64)
    ok "CPU architecture: ${ARCH}"
    ;;
  *)
    fail "CPU architecture is ${ARCH} (need x86_64 / amd64 for ubuntu/jammy64)"
    echo "  [FAIL] CPU architecture: ${ARCH}"
    ;;
esac

# --- Virtualization ---
if has_cpu_virt; then
  ok "CPU virtualization support (VT-x / AMD-V)"
else
  fail "CPU virtualization not detected (enable VT-x / AMD-V / nested virt in BIOS)"
  echo "  [FAIL] CPU virtualization support"
fi

# --- Tools ---
if command -v VBoxManage >/dev/null 2>&1; then
  ok "VirtualBox: $(VBoxManage --version 2>/dev/null | head -1)"
  # VirtualBox 6.1.28+ restricts host-only nets; lab uses 10.10.0.0/24
  if [[ -f /etc/vbox/networks.conf ]] && grep -Eq '10\.10\.0\.0/(24|16|8)' /etc/vbox/networks.conf; then
    ok "VirtualBox allows 10.10.0.0/24 (/etc/vbox/networks.conf)"
  elif [[ ! -f /etc/vbox/networks.conf ]]; then
    fail "VirtualBox networks.conf missing — 10.10.0.0/24 will be rejected"
    echo "  [FAIL] /etc/vbox/networks.conf (see docs/troubleshooting.md)"
  else
    fail "VirtualBox networks.conf does not allow 10.10.0.0/24"
    echo "  [FAIL] /etc/vbox/networks.conf missing 10.10.0.0/24"
  fi
  # KVM and VirtualBox cannot both own AMD-V / VT-x at once
  if lsmod 2>/dev/null | grep -qE '^kvm_(amd|intel)[[:space:]]'; then
    fail "KVM module loaded (kvm_amd/kvm_intel) — VirtualBox cannot use AMD-V/VT-x"
    echo "  [FAIL] KVM in use (see docs/troubleshooting.md: unload kvm before create)"
  else
    ok "KVM hardware virt module not loaded (VirtualBox can use AMD-V/VT-x)"
  fi
else
  fail "VirtualBox (VBoxManage) is not installed or not on PATH"
  echo "  [FAIL] VirtualBox"
fi

if command -v vagrant >/dev/null 2>&1; then
  ok "Vagrant: $(vagrant --version 2>/dev/null | head -1)"
else
  fail "Vagrant is not installed or not on PATH"
  echo "  [FAIL] Vagrant"
fi

if command -v git >/dev/null 2>&1; then
  ok "git: $(git --version 2>/dev/null)"
else
  fail "git is not installed"
  echo "  [FAIL] git"
fi

if command -v make >/dev/null 2>&1; then
  ok "make: $(make --version 2>/dev/null | head -1)"
else
  fail "make is not installed"
  echo "  [FAIL] make"
fi

if command -v node >/dev/null 2>&1; then
  ok "node: $(node -v 2>/dev/null) (dashboard only)"
else
  warn "node not found (needed only for make dashboard)"
fi

# --- RAM ---
GUEST_MB="$(required_guest_mb)"
# Guests + ~1 GiB host headroom
NEED_MB=$(( GUEST_MB + 1024 ))
TOTAL_MB="$(total_ram_mb)"
AVAIL_MB="$(available_ram_mb)"

if [[ "${TOTAL_MB}" -ge "${NEED_MB}" ]]; then
  ok "RAM total: ${TOTAL_MB} MB (need at least ~${NEED_MB} MB for ${GUEST_MB} MB guests + host)"
else
  fail "RAM total ${TOTAL_MB} MB is too low (need at least ~${NEED_MB} MB)"
  echo "  [FAIL] RAM total: ${TOTAL_MB} MB (need ~${NEED_MB} MB)"
fi

if [[ "${AVAIL_MB}" -gt 0 && "${AVAIL_MB}" -lt $(( GUEST_MB )) ]]; then
  warn "Available RAM looks low (${AVAIL_MB} MB); close other apps before create"
fi

# --- Disk ---
FREE_GB="$(disk_free_gb)"
# Six VMs (incl. cicd @ 2 GiB) need more disk headroom than the five-VM Insight lab.
MIN_DISK_GB=15
if [[ -n "${FREE_GB}" && "${FREE_GB}" -ge "${MIN_DISK_GB}" ]]; then
  ok "Disk free on /: ${FREE_GB} GB (need at least ${MIN_DISK_GB} GB)"
else
  fail "Disk free on / is ${FREE_GB:-unknown} GB (need at least ${MIN_DISK_GB} GB)"
  echo "  [FAIL] Disk space"
fi

echo ""

if [[ "${FAILED}" -ne 0 ]]; then
  echo "========================================"
  echo " Machine is not capable to run this"
  echo "========================================"
  echo ""
  echo "Reasons:"
  for r in "${REASONS[@]}"; do
    echo "  - ${r}"
  done
  echo ""
  echo "See docs/how-to-run.md (or README Prerequisites) for install steps, then re-run:"
  echo "  make check-host"
  echo "  make create"
  exit 1
fi

echo "========================================"
echo " Host check PASSED — machine can create VMs"
echo "========================================"
exit 0
