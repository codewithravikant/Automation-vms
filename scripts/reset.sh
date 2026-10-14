#!/usr/bin/env bash
# Destroy and recreate the full environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo " Automation-VMs — reset"
echo "========================================"

"${SCRIPT_DIR}/destroy.sh"
"${SCRIPT_DIR}/create.sh"
