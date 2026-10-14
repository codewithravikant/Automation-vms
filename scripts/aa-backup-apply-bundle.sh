#!/usr/bin/env bash
# Apply a backup bundle on an export host (appserver / web / lb).
# Must run as root. Restores the same prefixes the weekly export captures.
#
# Usage:
#   aa-backup-apply-bundle --dry-run [--with-etc] /path/to/bundle.tar.gz
#   aa-backup-apply-bundle --apply [--with-etc] /path/to/bundle.tar.gz

set -euo pipefail

APPLY=0
WITH_ETC=0
BUNDLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) APPLY=0; shift ;;
    --apply) APPLY=1; shift ;;
    --with-etc) WITH_ETC=1; shift ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      BUNDLE="$1"
      shift
      ;;
  esac
done

if [[ -z "${BUNDLE}" || ! -f "${BUNDLE}" ]]; then
  echo "Usage: $0 [--dry-run|--apply] [--with-etc] /path/to/bundle.tar.gz" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Must run as root" >&2
  exit 1
fi

HOST_NAME="$(hostname -s)"
MODE="$([[ ${APPLY} -eq 1 ]] && echo APPLY || echo DRY-RUN)"
echo "==> ${HOST_NAME}: bundle apply (${MODE})$([[ ${WITH_ETC} -eq 1 ]] && echo ' +etc' || true)"
echo "    source: ${BUNDLE}"

CANDIDATES=(home/devops var/lib/automation-alchemy)
if [[ "${WITH_ETC}" -eq 1 ]]; then
  CANDIDATES+=(etc)
fi

# List once to a tempfile — do NOT use tar|grep under pipefail (SIGPIPE false-negatives).
# GNU tar exits 2 when a named member is missing; only extract prefixes that exist.
MEMBERS="$(mktemp /tmp/aa-restore-members.XXXXXX)"
cleanup_members() { rm -f "${MEMBERS}"; }
trap cleanup_members EXIT

tar -tzf "${BUNDLE}" >"${MEMBERS}"

EXTRACT_ARGS=()
for prefix in "${CANDIDATES[@]}"; do
  if grep -qE "^${prefix}(/|$)" "${MEMBERS}"; then
    EXTRACT_ARGS+=("${prefix}")
  else
    echo "    skip missing prefix: ${prefix}"
  fi
done

if [[ ${#EXTRACT_ARGS[@]} -eq 0 ]]; then
  echo "ERROR: no extractable prefixes in bundle" >&2
  exit 1
fi

echo "    prefixes: ${EXTRACT_ARGS[*]}"
echo "    members matching prefixes (sample):"
grep -E "^($(IFS='|'; echo "${EXTRACT_ARGS[*]}"))(/|$)" "${MEMBERS}" | head -n 40 || true
member_count="$(grep -cE "^($(IFS='|'; echo "${EXTRACT_ARGS[*]}"))(/|$)" "${MEMBERS}" || true)"
echo "    member count (approx): ${member_count}"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "    dry-run only — no files written"
  exit 0
fi

TMP="$(mktemp -d /tmp/aa-restore.XXXXXX)"
cleanup() { rm -rf "${TMP}"; rm -f "${MEMBERS}"; }
trap cleanup EXIT

set +e
tar -C "${TMP}" -xzf "${BUNDLE}" \
  --exclude='var/lib/automation-alchemy/backup-export' \
  "${EXTRACT_ARGS[@]}" 2>/tmp/aa-restore-tar.err
tar_rc=$?
set -e
if [[ ${tar_rc} -ne 0 ]]; then
  cat /tmp/aa-restore-tar.err >&2 || true
  echo "tar extract failed (rc=${tar_rc})" >&2
  exit 1
fi

if [[ -d "${TMP}/home/devops" ]]; then
  echo "    restoring /home/devops"
  rsync -aH --numeric-ids "${TMP}/home/devops/" /home/devops/
  chown -R devops:devops /home/devops 2>/dev/null || true
fi

if [[ -d "${TMP}/var/lib/automation-alchemy" ]]; then
  echo "    restoring /var/lib/automation-alchemy (excluding backup-export)"
  mkdir -p /var/lib/automation-alchemy
  rsync -aH --numeric-ids \
    --exclude='backup-export' \
    "${TMP}/var/lib/automation-alchemy/" \
    /var/lib/automation-alchemy/
fi

if [[ "${WITH_ETC}" -eq 1 && -d "${TMP}/etc" ]]; then
  echo "    restoring /etc from bundle (WITH_ETC)"
  rsync -aH --numeric-ids "${TMP}/etc/" /etc/
fi

echo "    apply complete on ${HOST_NAME}"
