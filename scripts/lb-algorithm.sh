#!/usr/bin/env bash
# Switch LB algorithm and reload nginx on loadbalancer.
# Usage: ./scripts/lb-algorithm.sh weighted|least_conn|resource

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

ALGO="${1:-weighted}"
case "${ALGO}" in
  weighted|least_conn|least-conn|resource|adaptive|resource-based) ;;
  *)
    echo "Usage: $0 weighted|least_conn|resource" >&2
    exit 1
    ;;
esac

require_vagrant
guest_root loadbalancer "LB_ALGORITHM=${ALGO} bash /opt/automation-alchemy/provisioning/loadbalancer.sh"
echo "Load balancer algorithm set to ${ALGO}"
