#!/usr/bin/env bash
# Record what GitHub actually returns for one PR, as a fixture.
#
#   capture-pr-state.sh <owner/repo> <pr> <fixture-name>
#
# Writes tests/fixtures/pr-state/<fixture-name>.json: the exact payload
# `fetch-pr-state.sh` asks for, plus a `_captured` key naming where it came from.
#
# The `_captured` key rides inside the payload rather than beside it because a
# fixture and its provenance separate the moment either is moved, and a recorded
# payload nobody can place is a payload nobody can re-take. The normaliser reads
# named fields, so an extra key changes nothing about what the fixture exercises.
#
# ⚠️ WHAT THIS IS FOR, AND WHY A HAND-WRITTEN PAYLOAD IS NOT THE SAME THING.
# The states these fixtures hold are ones the suite cannot construct correctly
# from imagination: they encode which `mergeStateStatus` GitHub pairs with which
# `reviewDecision` under which branch protection. Every defect the merge-cause
# mapping shipped with was of that shape — a real combination nobody had seen —
# so a fixture invented to match the code under test would have reproduced the
# bug rather than caught it. Capture from a live PR, or do not add the case.
set -euo pipefail

REPO="${1:-}"; PR="${2:-}"; NAME="${3:-}"
[ -n "$REPO" ] && [ -n "$PR" ] && [ -n "$NAME" ] || {
  echo "usage: capture-pr-state.sh <owner/repo> <pr> <fixture-name>" >&2; exit 2; }
case "$REPO" in */*) ;; *) echo "repo must be owner/name" >&2; exit 2 ;; esac
case "$NAME" in *[!a-z0-9-]*) echo "fixture name: lowercase, digits, dashes" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/pr-state/$NAME.json"
mkdir -p "$HERE/pr-state"

# The same field list fetch-pr-state.sh asks for. Kept in step by
# tests/merge-cause.bats, so a field added there cannot leave the fixtures behind.
FIELDS=state,isDraft,headRefOid,reviews,comments,statusCheckRollup,mergeStateStatus,reviewDecision

RAW=$(gh pr view "$PR" --repo "$REPO" --json "$FIELDS")
PROT=$(gh api "repos/$REPO/branches/$(gh api "repos/$REPO" --jq .default_branch)/protection" \
         --jq '{approvals: (.required_pull_request_reviews.required_approving_review_count // 0),
                strict: (.required_status_checks.strict // false),
                conversation_resolution: (.required_conversation_resolution.enabled // false),
                required_checks: (.required_status_checks.contexts // [] | length)}' 2>/dev/null) \
  || PROT='{"note":"branch protection not readable with this token"}'

printf '%s' "$RAW" | jq --arg r "$REPO" --arg p "$PR" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson prot "$PROT" \
  '{_captured: {repo: $r, pr: ($p|tonumber), at: $at, protection: $prot}} + .' > "$OUT"

echo "wrote $OUT"
jq -r '"  mergeStateStatus=\(.mergeStateStatus)  reviewDecision=\"\(.reviewDecision)\"  checks=\([.statusCheckRollup[]? | "\(.name // .context):\(.status // .state)/\(.conclusion // "")"] | join(" "))"' "$OUT"
