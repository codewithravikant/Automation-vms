#!/usr/bin/env bash
# Build and deploy diagnostic app containers across the lab VMs.
# Backend → appserver; frontend → web1 + web2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${SCRIPT_DIR}/_common.sh"

BACKEND_IMAGE="automation-alchemy-backend:latest"
FRONTEND_IMAGE="automation-alchemy-frontend:latest"
APP_ROOT="/opt/automation-alchemy/app"

ip_for() {
  local want="$1"
  while IFS='|' read -r name ip; do
    if [[ "${name}" == "${want}" ]]; then
      echo "${ip}"
      return 0
    fi
  done < <(list_machines)
  return 1
}

echo "========================================"
echo " Automation-VMs — app deploy"
echo "========================================"

require_vagrant
ensure_ssh_key

APPSERVER_IP="$(ip_for appserver)"

echo "==> Building backend on appserver"
guest_root appserver "cd ${APP_ROOT}/backend && docker build -t ${BACKEND_IMAGE} ."

echo "==> Running backend on appserver (:3000)"
guest_root appserver "docker rm -f ii-backend >/dev/null 2>&1 || true; docker run -d --name ii-backend --restart unless-stopped -p 3000:3000 -e PORT=3000 ${BACKEND_IMAGE}; mkdir -p /var/lib/automation-alchemy; chown devops:devops /var/lib/automation-alchemy || true"

# web1/web2 are 512MB — npm/vite build OOMs there (docker exit 137). Build on appserver.
echo "==> Building frontend image on appserver"
guest_root appserver "cd ${APP_ROOT}/frontend && docker build -t ${FRONTEND_IMAGE} ."

echo "==> Transferring frontend image appserver → web1 → web2"
cd_infra
vagrant ssh appserver -c "sudo docker save ${FRONTEND_IMAGE}" | vagrant ssh web1 -c "sudo docker load"
vagrant ssh web1 -c "sudo docker save ${FRONTEND_IMAGE}" | vagrant ssh web2 -c "sudo docker load"

deploy_frontend() {
  local name="$1"
  local web_label="$2"
  echo "==> Running frontend on ${name} (:80 → API ${APPSERVER_IP}:3000)"
  guest_root "${name}" "docker rm -f ii-frontend >/dev/null 2>&1 || true; docker run -d --name ii-frontend --restart unless-stopped -p 80:80 -e BACKEND_HOST=${APPSERVER_IP} -e BACKEND_PORT=3000 -e WEB_SERVER=${web_label} ${FRONTEND_IMAGE}"
}

deploy_frontend web1 web1
deploy_frontend web2 web2

echo "==> Ensuring load balancer nginx is up"
guest_root loadbalancer "bash /opt/automation-alchemy/provisioning/loadbalancer.sh"

echo ""
echo "Deploy complete."
echo "  Open http://$(ip_for loadbalancer)/  (or http://10.10.0.10/)"
echo "  API via LB: http://10.10.0.10/api/metrics"
echo "  Direct API: http://${APPSERVER_IP}:3000/metrics"
echo "Next: make app-verify"
