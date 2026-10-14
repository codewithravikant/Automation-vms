#!/bin/bash
# Install base packages used on every VM (separate from networking/hosts).

set -euo pipefail

echo "==> Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq curl vim htop

echo "==> Base packages installed"
