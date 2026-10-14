#!/usr/bin/env bash
# Short latency check against the load balancer (pipeline Performance stage).

set -euo pipefail

URL="${1:-http://10.10.0.10/}"
SAMPLES="${SAMPLES:-5}"
MAX_AVG_MS="${MAX_AVG_MS:-2000}"

echo "========================================"
echo " Automation-VMs — perf check"
echo " URL: ${URL}  samples=${SAMPLES}  max_avg_ms=${MAX_AVG_MS}"
echo "========================================"

total=0
ok=0
for i in $(seq 1 "${SAMPLES}"); do
  # curl %{time_total} is seconds; convert to ms
  out="$(curl -fsS -o /dev/null -w '%{http_code} %{time_total}' --max-time 10 "${URL}" || echo "000 9.999")"
  code="$(echo "${out}" | awk '{print $1}')"
  secs="$(echo "${out}" | awk '{print $2}')"
  ms="$(awk -v s="${secs}" 'BEGIN { printf "%d", s * 1000 }')"
  echo "  sample ${i}: HTTP ${code}  ${ms} ms"
  if [[ "${code}" == "200" ]]; then
    ok=$((ok + 1))
    total=$((total + ms))
  fi
done

if [[ "${ok}" -lt 1 ]]; then
  echo "FAIL: no successful samples"
  exit 1
fi

avg=$((total / ok))
echo "Average latency: ${avg} ms (${ok}/${SAMPLES} ok)"
if [[ "${avg}" -gt "${MAX_AVG_MS}" ]]; then
  echo "FAIL: average ${avg} ms exceeds ${MAX_AVG_MS} ms"
  exit 1
fi

echo "PASS: latency within budget"
exit 0
