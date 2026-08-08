#!/usr/bin/env bash
# Block until a PR reaches a state the author has to act on, then print it and
# exit. Drives `git-workflow`'s merge watch: after a clean review the agent
# spawns this as a background task and gets exactly one wake — on the merge, on a
# conflict, on a terminal block, or once when the window runs out.
#
#   watch-merge.sh <owner/repo> <pr>
#
# Prints one result line, then the state line, then the raw JSON of the last
# successful poll, and exits 0:
#   result=MERGED now=<iso>       # merged — run post-merge cleanup
#   result=CLOSED now=<iso>       # closed unmerged — stop, leave the worktree
#   result=DIRTY now=<iso>        # conflict with base — surface and ask
#   result=BLOCKED now=<iso>      # terminal block, no checks pending — diagnose
#   result=TIMEOUT now=<iso>      # window elapsed, still open and mergeable
#   result=ERROR reason=<source> now=<iso>   # the watch is broken — no state line
#
# ERROR carries no state line and no JSON on purpose: the watch never got a look,
# so there is nothing true to say about the PR. Anything printed there would be
# stale or blank and would read as fact. It takes both FAIL_MAX ticks and
# FAIL_MIN_SECONDS of awake time, so a short outage is ridden out rather than
# ending a six-hour watch.
#
# This never merges anything. It only reads.
#
# Reads with the dev's own gh auth (not a short-lived bot token) so a long watch —
# including across laptop sleep — cannot expire its credential mid-poll.
set -euo pipefail
unset GH_TOKEN

REPO="${1:?owner/repo}"; PR="${2:?pr number}"

# shellcheck source=./lib-poll.sh
. "$(dirname "$0")/lib-poll.sh"

# Last successful poll. Held across a failed tick so a blip on the tick that
# happens to observe the deadline cannot erase what the watch already knew.
J=""; STATE=""; MSS=""; PENDING=""

report() {
  echo "result=$1 now=$(poll_now_iso)"
  echo "state=$STATE mergeStateStatus=$MSS pending_checks=$PENDING"
  echo "$J"
  exit 0
}

report_error() { echo "result=ERROR reason=$1 now=$(poll_now_iso)"; exit 0; }

fails_poll=0; fails_shape=0; fails_poll_since=0
poll_init

while :; do
  # Only the gh call is silenced: its failures are the transient ones, and its
  # stderr would otherwise land in the background task's result, making a watch
  # that rode out a blip and then reported MERGED read like one that died.
  if RAW=$(gh pr view "$PR" --repo "$REPO" \
             --json state,mergeStateStatus,statusCheckRollup,reviewDecision 2>/dev/null); then
    fails_poll=0
  else
    fails_poll=$(( fails_poll + 1 ))
    [ "$fails_poll" = 1 ] && fails_poll_since=$(poll_awake)
    poll_broken "$fails_poll" "$fails_poll_since" && report_error pr-view
    poll_reset
    # A window that runs out while gh is unreachable still reports what the last
    # good poll saw — but only if there was one. With no successful poll the
    # state fields are blank, and TIMEOUT would assert the PR is still open when
    # nothing is known about it at all.
    if poll_timed_out; then
      [ -n "$STATE" ] && report TIMEOUT
      report_error pr-view
    fi
    poll_nap; continue
  fi

  # Shape gate, counted separately from poll failures. A parse break here is not
  # transient — the call succeeded — and sharing the poll counter would cap it at
  # 1, since a successful poll resets that counter every tick.
  shape_ok=1
  S=$(echo "$RAW" | jq -r '.state // empty' 2>/dev/null) || shape_ok=0
  [ -n "${S:-}" ] || shape_ok=0
  # mergeStateStatus is gated exactly like state, and for the same reason. It is
  # the one field DIRTY and terminal-BLOCKED are read from, so an empty one
  # silently disables both for the rest of the window and the watch reports
  # TIMEOUT — which git-workflow reads as "still open and mergeable, remind the
  # operator". That is a positive claim about the PR, and it would be false on a
  # PR that is actually conflicted.
  M=$(echo "$RAW" | jq -r '.mergeStateStatus // empty' 2>/dev/null) || shape_ok=0
  [ -n "${M:-}" ] || shape_ok=0
  # PENDING counts checks that have not reached a terminal state. The rollup
  # holds two shapes: CheckRun uses .status (COMPLETED is terminal), StatusContext
  # uses .state (PENDING is not). Any non-terminal check means a BLOCKED is still
  # just auto-merge waiting. `// []` because statusCheckRollup is null on a PR
  # with no checks at all, and iterating null is a hard jq error.
  P=$(echo "$RAW" | jq -r '[(.statusCheckRollup // [])[]
        | select((.status != null and .status != "COMPLETED") or .state == "PENDING")]
        | length' 2>/dev/null) || shape_ok=0
  if [ "$shape_ok" = 0 ]; then
    fails_shape=$(( fails_shape + 1 ))
    [ "$fails_shape" -ge "$FAIL_MAX" ] && report_error pr-view-shape
    poll_reset
    if poll_timed_out; then
      [ -n "$STATE" ] && report TIMEOUT
      report_error pr-view-shape
    fi
    poll_nap; continue
  fi
  fails_shape=0
  J=$RAW; STATE=$S; MSS=$M; PENDING=$P

  # Terminal states, in the order the caller cares about. Evaluated after the
  # poll and before the deadline so a merge that happened during a suspend is
  # reported as MERGED on wake rather than as TIMEOUT.
  case $STATE in
    MERGED) report MERGED ;;
    CLOSED) report CLOSED ;;
  esac
  [ "$MSS" = DIRTY ] && report DIRTY
  # BLOCKED is a summary over unrelated conditions: a required check still
  # running (transient — auto-merge fires when it passes) and a failed check,
  # dismissed approval, unresolved thread, or out-of-date branch (terminal).
  # The pending count is what separates them; autoMergeRequest does not, because
  # GitHub leaves an auto-merge request in place when a required check fails.
  [ "$MSS" = BLOCKED ] && [ "$PENDING" = 0 ] && report BLOCKED

  poll_timed_out && report TIMEOUT
  # No poll_reset on a healthy tick: nothing has changed, and the curve widening
  # the longer a merge hasn't happened is the entire point of it.
  poll_nap
done
