#!/usr/bin/env bash
# One-click Alchemy: blank slate → 6 VMs → Ansible → registry/Jenkins → live app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

ANSIBLE_DIR="${ROOT}/automation"
TAG="${IMAGE_TAG:-}"

echo "========================================"
echo " Automation-VMs — make alchemy"
echo "========================================"

require_vagrant
ensure_ssh_key

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook not found on the control host." >&2
  echo "Install: pip install ansible   OR   brew install ansible" >&2
  exit 1
fi

echo "==> Host safety check"
bash "${SCRIPT_DIR}/check-host.sh"

echo "==> Creating / updating 6 VMs (Vagrant + Phase 1/2 bash bootstrap)"
cd_infra
vagrant up

echo "==> Waiting for devops SSH on all guests"
deadline=$((SECONDS + 300))
while IFS='|' read -r name ip; do
  echo "  - ${name} (${ip})"
  while (( SECONDS < deadline )); do
    if ssh_devops "${ip}" "echo ok" >/dev/null 2>&1; then
      echo "    SSH ready"
      break
    fi
    sleep 3
  done
  if ! ssh_devops "${ip}" "echo ok" >/dev/null 2>&1; then
    echo "ERROR: SSH not ready for ${name} (${ip})" >&2
    exit 1
  fi
done < <(list_machines)

echo "==> Ansible site.yml (idempotent harden/config)"
(
  cd "${ANSIBLE_DIR}"
  ansible-playbook playbooks/site.yml
)

echo "==> Ansible cicd.yml (Jenkins + registry)"
(
  cd "${ANSIBLE_DIR}"
  cicd_args=()
  if [[ "${ALCHEMY_FROM_JENKINS:-}" == "1" ]]; then
    echo "    Jenkins is running this build — do not stop or upgrade it"
    cicd_args+=(-e alchemy_from_jenkins=true)
  fi
  ansible-playbook playbooks/cicd.yml "${cicd_args[@]}"
)

if [[ -z "${TAG}" ]]; then
  if git -C "${ROOT}" rev-parse --short HEAD >/dev/null 2>&1; then
    TAG="$(git -C "${ROOT}" rev-parse --short HEAD)"
  else
    TAG="$(date -u +%Y%m%d%H%M%S)"
  fi
fi
echo "==> Initial image build/push on cicd (tag=${TAG})"

guest_root cicd "mkdir -p /var/lib/automation-alchemy && chown devops:devops /var/lib/automation-alchemy || true"
guest_root cicd "cd /opt/automation-alchemy/app/backend && docker build -t 10.10.0.40:5000/aa-backend:${TAG} -t 10.10.0.40:5000/aa-backend:latest ."
guest_root cicd "cd /opt/automation-alchemy/app/frontend && docker build -t 10.10.0.40:5000/aa-frontend:${TAG} -t 10.10.0.40:5000/aa-frontend:latest ."
guest_root cicd "docker push 10.10.0.40:5000/aa-backend:${TAG} && docker push 10.10.0.40:5000/aa-backend:latest"
guest_root cicd "docker push 10.10.0.40:5000/aa-frontend:${TAG} && docker push 10.10.0.40:5000/aa-frontend:latest"

echo "==> Ansible deploy.yml"
(
  cd "${ANSIBLE_DIR}"
  ansible-playbook playbooks/deploy.yml -e "image_tag=${TAG}"
)

echo "==> Smoke verify"
bash "${SCRIPT_DIR}/app-verify.sh" || {
  echo "WARN: app-verify reported failures — check containers / LB" >&2
}

LB_IP="10.10.0.10"
CICD_IP="10.10.0.40"

echo ""
echo "========================================"
echo " Alchemy ready"
echo "========================================"
echo "  App:     http://${LB_IP}/"
echo "  Metrics: http://${LB_IP}/api/metrics"
echo "  Jenkins: http://${CICD_IP}:8080/  (admin / devops)"
echo "  Registry: ${CICD_IP}:5000"
echo ""
echo "Re-run Ansible (idempotency):"
echo "  cd automation && ansible-playbook playbooks/site.yml"
echo "Rollback:"
echo "  make rollback"
echo "Insight-only path still works: make create && make app-deploy"
echo ""
if [[ "${SKIP_APT_UPGRADE:-}" == "1" ]]; then
  echo "Background apt upgrade skipped (SKIP_APT_UPGRADE=1)."
  echo "Run later: make apt-upgrade-bg"
else
  echo "==> Starting background apt upgrade (does not block this command)"
  bash "${SCRIPT_DIR}/apt-upgrade-guests.sh" --background || \
    echo "WARN: could not start background apt upgrade" >&2
fi
