#!/usr/bin/env bash
# Answer "is the standing verdict attached to the PR's current HEAD?" — the
# question both sides of a review ask, from opposite ends. `git-workflow` asks it
# before telling the operator a PR is ready to merge; `reviewer` asks it to decide
# whether its own verdict has been overtaken by a push.
#
#   pr-verdict.sh <owner/repo> <pr>
#
# Prints exactly one result line, then exits 0:
#   result=OK head=<sha> verdict=<state> verdict_sha=<sha> at_head=0|1
#   result=OK head=<sha> verdict=NONE verdict_sha= at_head=0   # no verdict yet
#   result=ERROR reason=bad-args|pr-view|pr-view-shape
#
# `verdict=APPROVED at_head=1` is the only combination that means HEAD is
# approved. Every other pairing is a different situation and the callers describe
# them differently, so the fields are printed separately rather than reduced to a
# single yes/no here.
#
# ⚠️ THE LAST VERDICT, NOT THE LAST APPROVAL. Filtering to `APPROVED` and taking
# the last one reads an `APPROVED` followed by a `CHANGES_REQUESTED` at the SAME
# SHA as approved — reachable two ways, a second reviewer objecting over a
# standing approval and a reviewer reversing itself after a reply. The first cut
# of this check had exactly that bug, in prose, in two skills at once.
#
# ⚠️ `COMMENTED` IS NOT A VERDICT and must stay out of the set. A reviewer
# answering a thread posts one, so counting it would blank the verdict on every
# exchange. `DISMISSED` is in the set because a dismissal genuinely ends the
# review it dismissed.
#
# This is the answer where no approval is REQUIRED. Where one is, `reviewDecision`
# is non-null and is the primary source — it accounts for supersession and for
# multiple required reviewers, neither of which this models. It is printed
# alongside so a caller can tell the two regimes apart without a second call.
#
# Do NOT reach for the branch-protection endpoint (`dismiss_stale_reviews`) to
# answer this instead: it needs admin, so it answers 403/404 on write-only
# access, and where it does answer it misleads — `dismiss_stale_reviews: true`
# with `required_approving_review_count: 0` means there is no approval gate to
# make stale. `tests/coupling.bats` bans the call outright.
set -euo pipefail

REPO="${1:-}"; PR="${2:-}"

# A result line rather than a silent `exit 1`, matching the watchers: callers
# branch on `result=`, so a typo must not present as the vanished-process case.
#
# The slash is checked even though nothing here splits on it — `--repo` is handed
# to gh whole. Without the check a malformed repo lands on `reason=pr-view`, which
# both calling skills gloss as "the check could not see", sending the caller to
# `gh auth status` when the fix is the argument they typed. Same reason the
# watchers separate `bad-args` from every other ERROR: one code, opposite remedies.
if [ -z "$REPO" ] || [ -z "$PR" ] || [ "$#" -gt 2 ] || [ "${REPO%/*}" = "$REPO" ]; then
  echo "result=ERROR reason=bad-args"
  exit 0
fi

if ! J=$(gh pr view "$PR" --repo "$REPO" --json headRefOid,reviews,reviewDecision 2>/dev/null); then
  echo "result=ERROR reason=pr-view"
  exit 0
fi

# One jq program, so a payload that stops parsing is one failure rather than
# three. `// empty` alone would not establish the FIELDS are present — an error
# body like `{"message":"Not Found"}` is well-formed JSON — so `headRefOid` is
# checked for emptiness below, the same gate watch-pr.sh applies to `.state`.
if ! OUT=$(echo "$J" | jq -r '
      (.reviews // [])
      | map(select(.state=="APPROVED" or .state=="CHANGES_REQUESTED" or .state=="DISMISSED"))
      | last as $v
      | [$v.state // "NONE", $v.commit.oid // ""] | @tsv' 2>/dev/null); then
  echo "result=ERROR reason=pr-view-shape"
  exit 0
fi

HEAD=$(echo "$J" | jq -r '.headRefOid // empty' 2>/dev/null || true)
if [ -z "$HEAD" ]; then
  echo "result=ERROR reason=pr-view-shape"
  exit 0
fi

DECISION=$(echo "$J" | jq -r '.reviewDecision // ""' 2>/dev/null || true)

IFS=$'\t' read -r VERDICT VSHA <<EOF
$OUT
EOF

AT_HEAD=0
[ -n "$VSHA" ] && [ "$VSHA" = "$HEAD" ] && AT_HEAD=1

echo "result=OK head=$HEAD verdict=$VERDICT verdict_sha=$VSHA at_head=$AT_HEAD review_decision=$DECISION"
