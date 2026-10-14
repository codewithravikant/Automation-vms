#!/usr/bin/env bash
# Run from Jenkins (cicd): SSH to the VirtualBox host, sync from Git, then deploy.
#
# Env:
#   AIWIN_SSH_HOST   default 10.10.0.1 (VirtualBox host from guest)
#   AIWIN_SSH_USER   default labuser
#   AIWIN_SSH_PORT   default 22
#   AIWIN_PROJECT    default ~/automation-vms
#   DEPLOY_MODE      app | infra  (required)
#   IMAGE_TAG        required when DEPLOY_MODE=app (registry tag from CI)
#   SSH_IDENTITY     default /var/lib/jenkins/.ssh/id_ed25519

set -euo pipefail

HOST="${AIWIN_SSH_HOST:-10.10.0.1}"
USER="${AIWIN_SSH_USER:-labuser}"
PORT="${AIWIN_SSH_PORT:-22}"
PROJECT="${AIWIN_PROJECT:-~/automation-vms}"
MODE="${DEPLOY_MODE:-}"
IDENTITY="${SSH_IDENTITY:-/var/lib/jenkins/.ssh/id_ed25519}"
IMAGE_TAG="${IMAGE_TAG:-}"

if [[ -z "${MODE}" ]]; then
  echo "ERROR: DEPLOY_MODE=app|infra required" >&2
  exit 1
fi

if [[ ! -f "${IDENTITY}" ]]; then
  echo "ERROR: SSH identity not found: ${IDENTITY}" >&2
  exit 1
fi

case "${MODE}" in
  app)
    if [[ -z "${IMAGE_TAG}" ]]; then
      echo "ERROR: IMAGE_TAG required for app deploy (registry aa-* tag)" >&2
      exit 1
    fi
    # Pull CI-built images from registry — do NOT use make app-deploy (ii-* rebuild).
    REMOTE_CMD=$(cat <<REMOTE
set -euo pipefail
cd ${PROJECT}
git fetch origin
if git show-ref --verify --quiet refs/remotes/origin/main; then
  git checkout main
  git reset --hard origin/main
elif git show-ref --verify --quiet refs/remotes/origin/master; then
  git checkout master
  git reset --hard origin/master
else
  echo "ERROR: origin/main or origin/master not found" >&2
  exit 1
fi
cd automation
ansible-playbook playbooks/deploy.yml -e "image_tag=${IMAGE_TAG}"
cd ..
make app-verify
REMOTE
)
    ;;
  infra)
    REMOTE_CMD=$(cat <<REMOTE
set -euo pipefail
cd ${PROJECT}
git fetch origin
if git show-ref --verify --quiet refs/remotes/origin/main; then
  git checkout main
  git reset --hard origin/main
elif git show-ref --verify --quiet refs/remotes/origin/master; then
  git checkout master
  git reset --hard origin/master
else
  echo "ERROR: origin/main or origin/master not found" >&2
  exit 1
fi
# cicd.yml must not stop or upgrade Jenkins while this build is running on it.
ALCHEMY_FROM_JENKINS=1 make alchemy
REMOTE
)
    ;;
  *)
    echo "ERROR: Unknown DEPLOY_MODE=${MODE}" >&2
    exit 1
    ;;
esac

echo "==> Remote ${USER}@${HOST}:${PORT} mode=${MODE} tag=${IMAGE_TAG:-n/a}"

ssh -i "${IDENTITY}" -p "${PORT}" \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=15 \
  "${USER}@${HOST}" \
  "bash -s" <<< "${REMOTE_CMD}"
