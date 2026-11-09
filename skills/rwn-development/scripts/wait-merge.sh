#!/usr/bin/env bash
# wait-merge.sh — block until one of the listed PRs is merged, then report the whole stack.
#
# Why: after a reviewer approves, the developer squash-merges the bottom PR of a stack by hand
# and previously had to tell the agent "merged it, go handle the next one". A blocking waiter
# turns that merge into an event: run it as a dsh background job and the session wakes when the
# merge lands, with no polling from the model.
#
# Usage: wait-merge.sh [--repo owner/repo] [--poll 30] [--timeout 43200] <pr> [<pr>...]
# Exit:  0 one PR merged | 1 every PR closed without a merge | 2 timed out
#
# GitHub offers no push channel a local CLI can subscribe to (only webhooks), so the wait
# necessarily polls — inside one background process, which costs no model turns. What must not
# happen is the *model* waking on a timer.
#
# The job only notifies on exit, so mid-wait events (review -> APPROVED) are logged for the
# record; only the merge/close/timeout ends it.
set -uo pipefail

usage() {
  printf '%s\n' \
    'Usage: wait-merge.sh [--repo owner/repo] [--poll 30] [--timeout 43200] <pr> [<pr>...]' \
    'Exit:  0 one PR merged | 1 every PR closed without a merge | 2 timed out'
}

REPO=""
POLL=30
TIMEOUT=43200
PRS=()

while (( $# > 0 )); do
  case "$1" in
    --repo) REPO="${2:?--repo needs owner/repo}"; shift 2 ;;
    --poll) POLL="${2:?--poll needs seconds}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 64 ;;
    *) PRS+=("$1"); shift ;;
  esac
done

(( ${#PRS[@]} > 0 )) || { usage >&2; exit 64; }
for n in "${PRS[@]}"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "not a PR number: $n" >&2; exit 64; }
done

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# One GraphQL round trip for the whole stack keeps the poll cheap.
QUERY="query{repository(owner:\"$OWNER\",name:\"$NAME\"){"
for n in "${PRS[@]}"; do
  QUERY+="p$n:pullRequest(number:$n){number state mergedAt reviewDecision}"
done
QUERY+="}}"

print_stack() {
  printf '%s\n' "$1" | awk -F'\t' '{printf "  #%s\t%s\treview=%s\n", $1, $2, $3}'
}

declare -A LAST=()
deadline=$(( $(date +%s) + TIMEOUT ))
merged=""

while :; do
  if ! rows=$(gh api graphql -f query="$QUERY" \
      -q '.data.repository|to_entries[]|[.value.number,.value.state,(.value.reviewDecision // "-")]|@tsv' 2>&1); then
    printf 'warn %s: api failed: %s\n' "$(date +%H:%M:%S)" "${rows%%$'\n'*}"
    sleep "$POLL"
    continue
  fi

  while IFS=$'\t' read -r num state review; do
    [[ -n "$num" ]] || continue
    if [[ "${LAST[$num]:-}" != "$state/$review" ]]; then
      printf '%s  #%s %s review=%s\n' "$(date +%H:%M:%S)" "$num" "$state" "$review"
      LAST[$num]="$state/$review"
    fi
    if [[ "$state" == "MERGED" && -z "$merged" ]]; then
      merged="$num"
    fi
  done <<< "$rows"

  if [[ -n "$merged" ]]; then
    printf '\n#%s merged — stack status:\n' "$merged"
    print_stack "$rows"
    exit 0
  fi

  # Every listed PR closed without a merge: the stack is dead, report instead of hanging.
  if ! printf '%s\n' "$rows" | awk -F'\t' 'BEGIN{open=0} $2!="CLOSED"{open=1} END{exit open?0:1}'; then
    printf '\nall PRs closed without a merge — stack status:\n'
    print_stack "$rows"
    exit 1
  fi

  if (( $(date +%s) >= deadline )); then
    printf '\nTIMEOUT after %ss — stack status:\n' "$TIMEOUT"
    print_stack "$rows"
    exit 2
  fi
  sleep "$POLL"
done
