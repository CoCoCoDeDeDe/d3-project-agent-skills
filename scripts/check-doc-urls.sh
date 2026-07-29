#!/usr/bin/env bash
# check-doc-urls.sh — verify every documentation path in doc-urls.md still
# resolves in the BabylonJS/Documentation repo. Exits non-zero if any 404.
#
# Usage:  scripts/check-doc-urls.sh
# Requires: bash, curl, grep, xargs. No node/python needed.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/skills/babylon-cad/references/doc-urls.md"
BASE="https://raw.githubusercontent.com/BabylonJS/Documentation/master/content"
JOBS=8

if [ ! -f "$FILE" ]; then
  echo "error: $FILE not found" >&2
  exit 2
fi

# Extract backtick-wrapped absolute doc paths (skips full https:// URLs and the {path} template)
mapfile -t PATHS < <(grep -oE '`/[a-zA-Z0-9/_-]+`' "$FILE" | tr -d '`' | sort -u)
TOTAL=${#PATHS[@]}
echo "checking $TOTAL doc paths from doc-urls.md ..."

check_one() {
  local base="$1" path="$2" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$base$path.md" || echo "curl-error")
  if [ "$code" != "200" ]; then
    echo "FAIL $path -> HTTP $code"
  fi
}
export -f check_one

FAILURES=$(printf '%s\n' "${PATHS[@]}" | xargs -P "$JOBS" -I% bash -c 'check_one "$0" "$1"' "$BASE" %)

if [ -n "$FAILURES" ]; then
  echo "$FAILURES"
  COUNT=$(echo "$FAILURES" | wc -l)
  echo "---"
  echo "$COUNT/$TOTAL paths broken"
  exit 1
fi

echo "all $TOTAL paths OK"
