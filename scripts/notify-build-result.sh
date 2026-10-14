#!/usr/bin/env bash
# Tell Slack how a Jenkins build ended. Never fails the caller.
#
# Usage (from a Jenkins pipeline post step):
#   ./scripts/notify-build-result.sh SUCCESS|FAILURE|ABORTED
#
# ABORTED is reported as "terminated" when the log shows Jenkins itself
# shut down or the build process was killed, and as "aborted" when a
# person stopped it.
# FAILURE includes the last real error from the build log.

set -euo pipefail

STATUS="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-/opt/automation-alchemy}"
WEBHOOK="${SLACK_WEBHOOK_FILE:-${PROJECT_ROOT}/automation/secrets/slack_webhook}"
NOTIFY="${ROOT}/scripts/notify-slack.sh"
LOG="${JENKINS_BUILD_LOG:-/var/lib/jenkins/jobs/${JOB_NAME:-alchemy-app}/builds/${BUILD_NUMBER:-0}/log}"

if [[ "${DEPLOY_MODE:-skip}" == "skip" ]]; then
  echo "Slack skipped — DEPLOY_MODE=skip"
  exit 0
fi

if [[ ! -x "${NOTIFY}" && -f "${NOTIFY}" ]]; then
  chmod +x "${NOTIFY}" || true
fi

clean_line() {
  sed -E 's/\x1b\[[0-9;]*m//g; s/^\[[0-9T:.-]+Z\] //' | tr -d '\r'
}

stage_log() {
  # Errors from the post block are not the reason the stages failed.
  if [[ -f "${LOG}" ]]; then
    awk '/Declarative: Post Actions/ { exit } { print }' "${LOG}"
  fi
}

pick_reason() {
  local src="$1" line
  line="$(printf '%s\n' "${src}" | clean_line \
    | grep -E 'ERROR!|ERROR:|npm ERR!|script returned exit code|No such DSL method|FATAL|Aborted by|Pausing \(shutting down\)|Terminated' \
    | grep -v 'Error when executing' \
    | tail -1 \
    | cut -c1-400 || true)"
  printf '%s' "${line}"
}

case "${STATUS}" in
  SUCCESS)
    LABEL="successful"
    REASON=""
    ;;
  FAILURE)
    LABEL="failed"
    REASON="$(pick_reason "$(stage_log)")"
    if [[ -z "${REASON}" && -f "${LOG}" ]]; then
      REASON="$(pick_reason "$(cat "${LOG}")")"
    fi
    [[ -n "${REASON}" ]] || REASON="see the build console"
    ;;
  ABORTED)
    full=""
    [[ -f "${LOG}" ]] && full="$(cat "${LOG}")"
    if printf '%s\n' "${full}" | grep -qE 'Pausing \(shutting down\)|JVM is terminating|Terminated'; then
      LABEL="terminated"
      REASON="$(pick_reason "${full}")"
      [[ -n "${REASON}" ]] || REASON="Jenkins shut down or the build process was killed"
    else
      LABEL="aborted"
      REASON="$(printf '%s\n' "${full}" | clean_line | grep -E 'Aborted by' | tail -1 | cut -c1-400 || true)"
      [[ -n "${REASON}" ]] || REASON="stopped before it finished"
    fi
    ;;
  *)
    echo "Usage: $0 SUCCESS|FAILURE|ABORTED" >&2
    exit 0
    ;;
esac

MSG="Automation-VMs *${JOB_NAME:-alchemy-app}* #${BUILD_NUMBER:-?} ${LABEL}"
MSG="${MSG} (mode ${DEPLOY_MODE:-?} tag ${IMAGE_TAG:-unknown})"
if [[ -n "${REASON}" ]]; then
  MSG="${MSG} — ${REASON}"
fi
if [[ "${STATUS}" == "SUCCESS" ]]; then
  MSG="${MSG} → http://10.10.0.10/"
fi
if [[ -n "${BUILD_URL:-}" ]]; then
  MSG="${MSG} (${BUILD_URL})"
fi

echo "Slack: ${MSG}"
if [[ ! -f "${NOTIFY}" ]]; then
  echo "notify-slack.sh missing — skipped"
  exit 0
fi
bash "${NOTIFY}" "${WEBHOOK}" "${MSG}" || true
exit 0
