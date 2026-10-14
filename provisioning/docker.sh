#!/bin/bash
# Install Docker Engine + Compose plugin on roles that host containers.
# Roles: appserver, web1, web2, cicd (Jenkins + registry). Not LB/backup.

set -euo pipefail

HOST_NAME="${VM_HOSTNAME:-$(hostname -s)}"

case "${HOST_NAME}" in
  appserver|web1|web2|cicd) ;;
  *)
    echo "==> Skipping Docker on ${HOST_NAME}"
    exit 0
    ;;
esac

echo "==> Installing Docker on ${HOST_NAME}"
export DEBIAN_FRONTEND=noninteractive

apt-get install -y -qq ca-certificates curl gnupg

# Prefer Ubuntu docker.io + compose plugin for a simple lab install
apt-get install -y -qq docker.io docker-compose-v2 || apt-get install -y -qq docker.io

systemctl enable docker
systemctl start docker

# Allow devops to run docker without root
if id devops >/dev/null 2>&1; then
  usermod -aG docker devops || true
fi

docker --version || true
docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true

echo "==> Docker ready on ${HOST_NAME}"
