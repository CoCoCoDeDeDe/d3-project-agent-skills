#!/usr/bin/env bash
# wait-ci.sh — block until every check on a PR's head commit reaches a terminal state.
#
# Why this exists: polling CI with `sleep` + "is it done yet" burns a model turn per
# interval. A blocking waiter can be launched as a dsh background job instead, so the
# agent is woken exactly once — when CI is actually done — and can spend the wait on
# useful work (PR body, review reading) instead of idling.
#
# Usage: wait-ci.sh <pr-number> [owner/repo] [poll-seconds] [timeout-seconds]
#   owner/repo   defaults to the repo of the current directory
#   poll         20 s — gh api calls are cheap; the point is not to poll from the model
#   timeout      2700 s (45 min), enough for the 5–8 min pipeline plus a slow review job
#
# Exit codes: 0 every check passed | 1 at least one check failed | 2 timed out
#
# The tail of the output is the review verdict (reviewDecision + unresolved
# review threads). A passing `code-review` check only means the review job ran
# to completion — the reviewer may still have posted CHANGES_REQUESTED with
# inline findings. Never read a green check as "no findings".
#
# Note: a PR whose base branch is not merged yet may never get checks at all — that is
# indistinguishable from "CI has not started" here, so it waits until the timeout.
set -uo pipefail

PR="${1:?usage: wait-ci.sh <pr-number> [owner/repo] [poll=20] [timeout=2700]}"
REPO="${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
POLL="${3:-20}"
TIMEOUT="${4:-2700}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

QUERY='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){commits(last:1){nodes{commit{oid statusCheckRollup{state}}}}}}}'

deadline=$(( $(date +%s) + TIMEOUT ))
last=""
state="UNKNOWN"

while :; do
  if out=$(gh api graphql -f query="$QUERY" -F owner="$OWNER" -F repo="$NAME" -F pr="$PR" \
      -q '.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.state // "NONE"' 2>&1); then
    state="$out"
  else
    # Network/API hiccup is not a CI verdict — log it and keep waiting.
    printf 'warn %s: api failed: %s\n' "$(date +%H:%M:%S)" "${out%%$'\n'*}"
    state="RETRY"
  fi

  if [[ "$state" != "$last" ]]; then
    printf '%s  state=%s\n' "$(date +%H:%M:%S)" "$state"
    last="$state"
  fi

  case "$state" in
    SUCCESS|FAILURE|ERROR) break ;;
  esac

  if (( $(date +%s) >= deadline )); then
    printf 'TIMEOUT after %ss (last state: %s)\n' "$TIMEOUT" "$state"
    gh pr checks "$PR" -R "$REPO" 2>&1 || true
    exit 2
  fi
  sleep "$POLL"
done

# Per-check detail, so the agent can name the failing job without a second round trip.
gh pr checks "$PR" -R "$REPO" 2>&1 || true

# --- Review verdict ---------------------------------------------------------
# A green `code-review` check only means the review job finished; the verdict
# (APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED) and the unresolved review
# threads live on the review, not on the check. Printing both here is the
# difference between "the job passed" and "the review approved".
printf '\n--- review verdict (a green check is NOT an approval) ---\n'
gh pr view "$PR" -R "$REPO" --json reviewDecision,reviews \
  --jq '"reviewDecision: " + (.reviewDecision // "NONE") + "\nreviews:\n" + ([.reviews[] | select(.state != "COMMENTED") | "  " + .state + " by " + .author.login + " at " + (.submittedAt // "?")] | join("\n"))' \
  2>&1 || printf 'warn: review query failed\n'

REVIEW_THREADS_QUERY='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:1){nodes{author{login} body}}}}}}}'
gh api graphql -f query="$REVIEW_THREADS_QUERY" -F owner="$OWNER" -F repo="$NAME" -F pr="$PR" \
  --jq '([.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | "unresolved review threads: " + (length|tostring)), (.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | "  - " + (.path // "?") + ":" + ((.line // 0)|tostring) + " [" + .id + "] (" + (.comments.nodes[0].author.login // "?") + ") " + ((.comments.nodes[0].body | split("\n")[0]) // ""))' \
  2>&1 || printf 'warn: review threads query failed\n'

if [[ "$state" == "SUCCESS" ]]; then
  printf '\nNOTE: CI is green, but read the review verdict above before reporting "no issues".\n'
  exit 0
fi
exit 1
