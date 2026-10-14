#!/usr/bin/env bash
# Classify git path changes for Jenkins / local CI routing.
# Prints one line: skip | app | infra
#
# Usage (from a git checkout):
#   ./scripts/classify-git-changes.sh
#   ./scripts/classify-git-changes.sh HEAD~1 HEAD

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if ! git rev-parse HEAD >/dev/null 2>&1; then
  echo "infra"
  exit 0
fi

COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
if [[ "${COUNT}" -le 1 ]]; then
  # First commit — full deployment
  echo "infra"
  exit 0
fi

FROM="${1:-HEAD~1}"
TO="${2:-HEAD}"

app=0
infra=0

is_docs_like() {
  local f="$1"
  case "${f}" in
    test/ci-sandbox|test/ci-sandbox/*) return 1 ;;
    README.md|LICENSE|LICENSE.md|docs|docs/*|.cursor|.cursor/*) return 0 ;;
  esac
  case "${f}" in
    *.md)
      case "${f}" in
        app/*|automation/*|test/ci-sandbox/*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
  esac
  return 1
}

while IFS= read -r f; do
  [[ -z "${f}" ]] && continue
  case "${f}" in
    app|app/*) app=1 ;;
    # Sandbox for webhook demos (add/edit/delete → same as app path)
    test/ci-sandbox|test/ci-sandbox/*) app=1 ;;
    automation|automation/*) infra=1 ;;
    *)
      if is_docs_like "${f}"; then
        :
      else
        :
      fi
      ;;
  esac
done < <(git diff --name-only "${FROM}" "${TO}" 2>/dev/null || true)

# Locked rules:
# - automation/ (alone or with app/) → infra (make alchemy)
# - app/ or test/ci-sandbox/ → app
# - docs-only / other → skip
if [[ "${infra}" -eq 1 ]]; then
  echo "infra"
elif [[ "${app}" -eq 1 ]]; then
  echo "app"
else
  echo "skip"
fi
