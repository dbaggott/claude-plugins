#!/usr/bin/env bash
# Everything one watch tick needs to know about a pull request, as one
# forge-neutral object.
#
#   fetch-pr-state.sh <owner/repo> <pr>
#
# Prints the object on ONE line, then exactly one result line, then exits 0 —
# two lines total, so a reader takes either with `head -1` / `tail -1`:
#   {"state":…,"draft":…,"head":…,"merge":{…},"checks":[…],"reviews":[…],"comments":[…],"inline":[…]}
#   result=OK now=<iso> [degraded=<source>]
#   result=ERROR reason=bad-args|pr-view|pr-view-shape now=<iso>
#
# One call per question would cost this tick three or four requests on a curve
# whose floor is ten seconds, so the unit here is the tick rather than the
# question. Which fields a forge can answer together is a forge's own business:
# GitHub needs a second request for inline comments, GitLab's discussions arrive
# with the MR.
#
# `degraded=<source>` reports a source that failed while others answered — the
# object is emitted without it rather than the whole tick being lost. The caller
# grades a degraded source on its own counter, since one source failing forever
# while the rest answer is a blind watch wearing a healthy one's costume.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB HERE, AND THAT IS THE ONE THING IN THIS
# FILE THAT IS NOT YET TRUE IN GENERAL. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection and adds sibling backends; the
# split between `normalise` and the fetch exists so that change touches one
# function. Nothing above this line is GitHub-shaped — that is the contract.
set -euo pipefail

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO="${1:-}"; PR="${2:-}"
case "${REPO}${PR}" in *[!\ ]*) ;; *) fail bad-args ;; esac
[ -n "$REPO" ] && [ -n "$PR" ] || fail bad-args
# Refused here rather than left to the forge: a typo'd repo is otherwise
# FAIL_MAX ticks of "the source is failing", whose documented remedy is checking
# auth — the one place the answer is not.
case "$REPO" in */*) ;; *) fail bad-args ;; esac
case "$PR" in *[!0-9]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

# --- GitHub backend ---------------------------------------------------------

# `statusCheckRollup` and `mergeStateStatus` ride along with the fields the tick
# already needed, so covering merge state and checks costs no extra request.
RAW=$(gh pr view "$PR" --repo "$REPO" \
        --json state,isDraft,headRefOid,reviews,comments,statusCheckRollup,mergeStateStatus,reviewDecision \
        2>/dev/null) || fail pr-view

DEGRADED=""
INLINE=$(gh api "repos/$REPO/pulls/$PR/comments?per_page=100&sort=created&direction=desc" \
           2>/dev/null) || { INLINE='[]'; DEGRADED="inline-comments"; }

# GitHub overloads one status where GitLab names the cause directly, so the
# counting that separates "a required check is still running" from "one failed"
# belongs to this backend and must not reach the caller.
#
# Two rollup shapes: CheckRun carries .name/.status/.conclusion, StatusContext
# .context/.state. A check that has not finished carries no conclusion.
OUT=$(jq -cn --argjson pr "$RAW" --argjson inline "$INLINE" '
  # Four states, rather than whatever vocabulary a forge uses. A CheckRun carries .status and, once
  # finished, .conclusion; a StatusContext carries .state. Handing those through
  # raw makes every caller re-derive "is this passing", and a caller that misses
  # one spelling reads a running check as a failed one.
  def check_state:
    (if (.conclusion // "") == "" then (.status // .state // "") else .conclusion end
     | ascii_downcase) as $c
    | if   $c == "success" then "success"
      elif $c == "neutral" or $c == "skipped" then "neutral"
      elif $c == "" or $c == "pending" or $c == "queued" or $c == "in_progress"
           or $c == "waiting" or $c == "requested" or $c == "expected" then "pending"
      else "failure" end;

  ($pr.statusCheckRollup // []) | map({
      name: (.name // .context // "?"),
      state: check_state
    }) as $checks
  | ($checks | map(select(.state == "pending"))) as $running
  | {
      state:  ($pr.state // ""),
      draft:  (if $pr.isDraft == null then null else $pr.isDraft end),
      head:   ($pr.headRefOid // ""),
      checks: $checks,
      merge: (
        ($pr.mergeStateStatus // "") as $m
        | if   $m == "CLEAN"    then {status:"clean",    cause:null}
          elif $m == "DIRTY"    then {status:"dirty",    cause:"conflict"}
          elif $m == "UNSTABLE" then {status:"unstable", cause:"checks_not_passing"}
          elif $m == "BLOCKED"  then
            # Four different waits arrive as one status, and a caller told
            # "terminal" stops watching — so every cause that a push or a review
            # will clear has to be named here. What is left for `terminal` is a
            # block with an approval in hand, nothing running and nothing red:
            # branch protection, a merge queue, an unresolved conversation. Only
            # those need a human.
            (if ($running | length) > 0
             then {status:"blocked", cause:"checks_running"}
             elif ($checks | map(select(.state == "failure")) | length) > 0
             then {status:"blocked", cause:"checks_failing"}
             elif ($pr.reviewDecision // "") == "REVIEW_REQUIRED"
               or ($pr.reviewDecision // "") == "CHANGES_REQUESTED"
             then {status:"blocked", cause:"review_required"}
             else {status:"blocked", cause:"terminal"} end)
          elif $m == ""         then {status:"unknown", cause:null}
          else {status:"unknown", cause:($m | ascii_downcase)} end
      ),
      reviews:  ($pr.reviews  // [] | map({author:(.author.login // ""), at:(.submittedAt // ""),
                                           state:(.state // ""), sha:(.commit.oid // ""),
                                           body:(.body // "")})),
      comments: ($pr.comments // [] | map({author:(.author.login // ""), at:(.createdAt // ""),
                                           body:(.body // "")})),
      inline:   ($inline      // [] | map({author:(.user.login // ""), at:(.created_at // ""),
                                           id:(.id // null), path:(.path // ""),
                                           line:(.line // .original_line // null),
                                           body:(.body // "")}))
    }' 2>/dev/null) || fail pr-view-shape

# The fields the caller branches on must be present, not merely parseable: an
# error body is well-formed JSON, and a missing `state` reads as neither MERGED
# nor CLOSED for the life of the watch.
echo "$OUT" | jq -e '.state != "" and .head != "" and .draft != null' >/dev/null 2>&1 \
  || fail pr-view-shape

echo "$OUT"
echo "result=OK now=$(now_iso)${DEGRADED:+ degraded=$DEGRADED}"
