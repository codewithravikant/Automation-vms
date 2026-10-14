#!/bin/bash
# VirtualBox NAT in this lab often cannot open archive.ubuntu.com:80.
# The same hosts answer on HTTPS. Idempotent.

set -euo pipefail

shopt -s nullglob
for src in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
  [[ -f "${src}" ]] || continue
  sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g' \
    "${src}"
done

cat >/etc/apt/apt.conf.d/80-acquire-retries <<'EOF'
APT::Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF
chmod 644 /etc/apt/apt.conf.d/80-acquire-retries
