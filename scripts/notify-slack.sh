#!/usr/bin/env bash
# Optional Slack notify helper (non-Jenkins callers).
# Usage: notify-slack.sh /path/to/slack_webhook "message"
# Secret file may contain:
#   xoxb-...  → Slack Web API chat.postMessage (bot token)
#   https://hooks.slack.com/... → Incoming Webhook
# Missing file / blank / comment → skip. Never fails the caller.

set -euo pipefail

WH="${1:-}"
TEXT="${2:-}"
CHANNEL="${SLACK_CHANNEL:-#jenkins-builds}"

if [[ -z "${WH}" || ! -f "${WH}" ]]; then
  echo "Slack not configured — skipped"
  exit 0
fi

SECRET="$(tr -d '[:space:]' < "${WH}" || true)"
if [[ -z "${SECRET}" || "${SECRET}" == \#* ]]; then
  echo "Slack secret empty or commented — skipped"
  exit 0
fi

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/}
  printf '%s' "${s}"
}

if [[ "${SECRET}" == xoxb-* ]]; then
  payload="{\"channel\":\"$(json_escape "${CHANNEL}")\",\"text\":\"$(json_escape "${TEXT}")\"}"
  if ! curl -fsS -X POST \
    -H "Authorization: Bearer ${SECRET}" \
    -H "Content-type: application/json; charset=utf-8" \
    --data "${payload}" \
    "https://slack.com/api/chat.postMessage" \
    | grep -q '"ok":true'; then
    echo "Slack bot notify failed — continuing"
  fi
  exit 0
fi

case "${SECRET}" in
  https://*) ;;
  *)
    echo "Slack secret is neither xoxb- token nor https webhook — skipped"
    exit 0
    ;;
esac

payload="{\"text\":\"$(json_escape "${TEXT}")\"}"
if ! curl -fsS -X POST -H 'Content-type: application/json' --data "${payload}" "${SECRET}"; then
  echo "Slack webhook notify failed — continuing"
fi
exit 0
