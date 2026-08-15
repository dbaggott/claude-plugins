#!/usr/bin/env bash
# Answer "is the standing verdict attached to the PR's current HEAD?" — the
# question both sides of a review ask, from opposite ends. `git-workflow` asks it
# before telling the operator a PR is ready to merge; `reviewer` asks it to decide
# whether its own verdict has been overtaken by a push.
#
#   pr-verdict.sh <owner/repo> <pr>
#
# Prints exactly one result line, then exits 0:
#   result=OK head=<sha> verdict=<state> verdict_sha=<sha> at_head=0|1 \
#     reviewed_after_head=0|1|unknown review_decision=<state>
#   result=ERROR reason=bad-args|pr-view|pr-view-shape
#
# `verdict=APPROVED at_head=1 reviewed_after_head=1` is the only combination that
# means HEAD is approved. Every other pairing is a different situation and the
# callers describe them differently, so the fields are printed separately rather
# than reduced to a single yes/no here.
#
# ⚠️ `at_head` ALONE DOES NOT MEAN HEAD HAS BEEN REVIEWED. A force-push moves an
# existing review's `commit_id` onto the rewritten commit — observed on
# https://github.com/dbaggott/claude-plugins/pull/168, a review submitted 18:44:21Z
# reporting a commit created 18:46:23Z. SHA and tree comparisons are both defeated
# by that rewrite (the re-anchored review's tree IS head's tree), so this compares
# the two things it cannot touch: `reviewed_after_head=1` means the standing
# verdict was submitted after the commit at head was created. Both dates come from
# the `gh pr view` already made here, so it costs no extra request.
#
# `unknown` means the comparison could not be made — no `commits` field, or head
# absent from it. It must never collapse to `1`. On a PR past one page of commits
# (see the jq below) it is permanent rather than one round's answer, so a caller
# waiting for it to clear waits forever.
#
# Three gaps. Fail-closed: a force-push that resets to an OLDER commit (the SHA
# comparison catches that one instead), and a committer clock ahead of GitHub's,
# which reads a genuine review as predating head until the next one lands.
# Fail-OPEN, so the one to weigh: a rewrite that preserves committer dates
# (`--committer-date-is-author-date`, `GIT_COMMITTER_DATE` by hand) leaves the
# rewritten commit dated before the review re-anchored onto it. Both opt-in —
# GitHub's own rebase paths stamp the committer date at rewrite time. Deduced
# from the flag's semantics; the re-anchoring has not been reproduced under it.
#
# Whether GitHub's "Update branch" emits `head_ref_force_pushed` is UNTESTED: its
# rebase variant rewrites and so can re-anchor, and only its merge variant is
# reachable from the REST endpoint. The date comparison covers both either way —
# settle it before reaching for the timeline event instead.
#
# The last verdict, not the last approval. Filtering to `APPROVED` and taking
# the last one reads an `APPROVED` followed by a `CHANGES_REQUESTED` at the SAME
# SHA as approved — reachable two ways, a second reviewer objecting over a
# standing approval and a reviewer reversing itself after a reply.
#
# `COMMENTED` is not a verdict and must stay out of the set. A reviewer
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

if ! J=$(gh pr view "$PR" --repo "$REPO" --json headRefOid,reviews,reviewDecision,commits 2>/dev/null); then
  echo "result=ERROR reason=pr-view"
  exit 0
fi

# One jq program, so a payload that stops parsing is one failure rather than
# three. `// empty` alone would not establish the FIELDS are present — an error
# body like `{"message":"Not Found"}` is well-formed JSON — so `headRefOid` is
# checked for emptiness below, the same gate watch-pr.sh applies to `.state`.
#
# Head is located by oid rather than taken as the last commit: the field asks for
# `commits(first: 100)`, so past that the last entry is not head, and matching
# lands on `unknown` instead of comparing against the wrong one. The two dates are
# compared as strings, which orders these correctly because GitHub returns both
# in the same fixed-width UTC form.
if ! OUT=$(echo "$J" | jq -r '
      . as $root
      | ($root.commits // []) | map(select(.oid == $root.headRefOid)) | last as $h
      | ($root.reviews // [])
      | map(select(.state=="APPROVED" or .state=="CHANGES_REQUESTED" or .state=="DISMISSED"))
      | last as $v
      | [$v.state // "NONE",
         (if ($h.committedDate // "") == "" then "unknown"
          elif $v == null then "0"
          elif ($v.submittedAt // "") == "" then "unknown"
          elif $v.submittedAt > $h.committedDate then "1"
          else "0" end),
         $v.commit.oid // ""] | @tsv' 2>/dev/null); then
  echo "result=ERROR reason=pr-view-shape"
  exit 0
fi

HEAD=$(echo "$J" | jq -r '.headRefOid // empty' 2>/dev/null || true)
if [ -z "$HEAD" ]; then
  echo "result=ERROR reason=pr-view-shape"
  exit 0
fi

DECISION=$(echo "$J" | jq -r '.reviewDecision // ""' 2>/dev/null || true)

# `verdict_sha` is read last because it is the only one of the three that can be
# empty, and a tab IFS collapses an empty field between two others.
IFS=$'\t' read -r VERDICT REVIEWED_AFTER VSHA <<EOF
$OUT
EOF

AT_HEAD=0
[ -n "$VSHA" ] && [ "$VSHA" = "$HEAD" ] && AT_HEAD=1

echo "result=OK head=$HEAD verdict=$VERDICT verdict_sha=$VSHA at_head=$AT_HEAD" \
     "reviewed_after_head=$REVIEWED_AFTER review_decision=$DECISION"
