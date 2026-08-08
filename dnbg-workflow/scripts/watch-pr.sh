#!/usr/bin/env bash
# Block until a reviewable change appears on a PR, then print what changed and
# exit. Drives the `reviewer` skill's in-session watch loop: after a review the
# agent spawns this as a background task; when it returns, the agent
# re-reviews/responds and re-arms it. Detects new commits, new (non-bot)
# reviews/comments/replies, a draft being marked ready, and the PR closing.
#
#   watch-pr.sh <owner/repo> <pr> <last_head_sha> <since_iso> <bot_slug> [--was-draft]
#
# bot_slug is the App slug WITHOUT the [bot] suffix. Both forms are excluded:
# gh pr view (GraphQL) reports a Bot author's login as `<slug>`, while gh api
# (REST) reports `<slug>[bot]` — so the bot never wakes itself.
#
# --was-draft arms the draft->ready check. Pass it when watching a PR you are
# deliberately NOT reviewing because it is still a draft; without it a ready
# transition is ignored, which is right for a PR already under review (it cannot
# go back to draft mid-review in any way that should re-trigger one).
#
# Prints exactly one result line, then exits 0:
#   result=COMMITS new_head=<sha> activity=0|1 now=<iso>  # author pushed
#   result=ACTIVITY activity=1 now=<iso>                  # review/comment/reply, not the bot's
#   result=READY new_head=<sha> activity=0|1 now=<iso>    # draft marked ready — only with --was-draft
#   result=CLOSED state=MERGED|CLOSED                     # PR finished — stop watching
#   result=IDLE now=<iso>                                 # nothing within the window — re-arm
#   result=ERROR reason=<source> now=<iso>                # the watch itself is broken — do NOT re-arm
#
# ERROR is not IDLE. IDLE means the PR was quiet; ERROR means one source failed
# FAIL_MAX ticks running and the watch cannot see. Both callers stop and tell the
# operator what to check (gh auth, the number/repo pair) rather than re-arming
# into the same failure.
#
# `activity=1` on a COMMITS or READY result means comments or replies landed in
# the same burst. The primary result names what to do first; the flag says there
# is also unread conversation. Ignoring it loses those replies for good, because
# the agent re-arms with since_iso set to now.
#
# Reads with the dev's own gh auth (not the short-lived bot token) so a long watch —
# including across laptop sleep — doesn't expire its credential mid-poll.
set -euo pipefail
unset GH_TOKEN   # use the dev's own (non-expiring) gh auth for the long poll

# --issue switches what is watched, not how: the curve, the awake clock and the
# failure counting are the same code either way (lib-poll.sh), which is why this
# is a mode rather than a sibling script. What separates a mode from a sibling is
# whether the *result* means something different — watch-merge.sh is a sibling
# because MERGED/DIRTY/BLOCKED are not COMMITS/ACTIVITY with a different label.
ISSUE_MODE=0; [ "${1:-}" = "--issue" ] && { ISSUE_MODE=1; shift; }
REPO="${1:?owner/repo}"; PR="${2:?pr or issue number}"
LAST_HEAD="${3:-}"; SINCE="${4:-1970-01-01T00:00:00Z}"; SLUG="${5:-}"
WAS_DRAFT=0; [ "${6:-}" = "--was-draft" ] && WAS_DRAFT=1

# The poll curve, the awake clock, FAIL_MAX and WINDOW all come from here. This
# script's own default window is the shared 6h: unlike git-workflow's watchers
# (where a timeout means "something's wrong — wake once, don't re-spawn"), IDLE
# here is routine, since a quiet PR is expected and the agent simply re-arms.
# shellcheck source=./lib-poll.sh
. "$(dirname "$0")/lib-poll.sh"

# Settle window. An author's round is a burst — reply to three threads, then push
# the fix — but a webhook-driven bot sees one event per action while this sees
# whichever it polls into first. Returning on that first sighting is not merely
# mis-ordered, it is lossy: the agent re-arms with `since_iso` set to now, so
# replies made before the wake but never read are filtered out permanently rather
# than deferred to the next wake.
#
# So once something changes, keep polling until SETTLE seconds pass with nothing
# further, and report the whole burst at once. SETTLE_MAX caps it so an author
# who keeps working can't hold the watch open indefinitely.
#
# Deliberately wall-clock, not awake time, and the only duration here that is.
# SETTLE exists to coalesce one author's burst of actions; a machine that
# suspended mid-burst has ended it by definition, so releasing immediately on
# wake is right. Charging it awake-seconds would hold a hours-old burst back
# waiting for quiet that already happened.
SETTLE=${SETTLE:-45}
SETTLE_MAX=${SETTLE_MAX:-300}

fails_primary=0; fails_comments=0; fails_shape=0
poll_init

# A burst in hand outranks ERROR: the observed activity is real, and reporting
# ERROR instead would send the caller to re-arm straight back into the failure
# while silently dropping what was already seen. Same invariant the idle path
# enforces.
report_error() {
  [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] && report_burst
  echo "result=ERROR reason=$1 now=$(poll_now_iso)"
  exit 0
}

# Report the accumulated burst. Defined once because two paths reach it — the
# quiet-period exit below, and the unreachable-gh path at the top of the loop,
# which must not silently drop a burst it can no longer confirm quiet.
report_burst() {
  if [ "$saw_commits" = 1 ]; then
    echo "result=COMMITS new_head=$new_head activity=$saw_activity now=$(poll_now_iso)"
  else
    echo "result=ACTIVITY activity=1 now=$(poll_now_iso)"
  fi
  exit 0
}

# What the burst contained. `obs_*` track the last values already accounted for,
# so a *second* push or reply during the window registers as new and extends it
# rather than re-reporting the same one forever.
saw_commits=0; saw_activity=0; new_head=""
obs_head="$LAST_HEAD"; obs_new=0; obs_newc=0
settle_until=0; settle_cap=0
# Initialised here, not left to the per-tick assignment: the unreachable-gh path
# reads it before any successful tick may have run. Today that is safe only
# because `settle_until != 0` implies one has — a coincidence, not a guarantee.
holding_draft=0

# Each jq program defines `mine` (true if a login is the bot, in either API's
# form). $slug/$s are jq vars from --arg, so the program stays single-quoted.

while :; do
  # Tolerate transient gh/network failures — skip the tick rather than dying
  # (set -e would otherwise kill the watch on a blip; an empty value must not
  # be read as a change).
  if [ "$ISSUE_MODE" = 1 ]; then
    poll_ok=0
    J=$(gh issue view "$PR" --repo "$REPO" --json state,closedByPullRequestsReferences 2>/dev/null) && poll_ok=1
  else
    poll_ok=0
    J=$(gh pr view "$PR" --repo "$REPO" --json state,isDraft,headRefOid,reviews,comments 2>/dev/null) && poll_ok=1
  fi
  if [ "$poll_ok" = 0 ]; then
    fails_primary=$(( fails_primary + 1 ))
    # A source that has failed FAIL_MAX ticks running is not a blip. Without
    # this the watch runs out its window and prints the line a genuinely quiet
    # PR prints, so a caller cannot tell a broken watch from a calm one.
    [ "$fails_primary" -ge "$FAIL_MAX" ] && report_error "$([ "$ISSUE_MODE" = 1 ] && echo issue-view || echo pr-view)"
    poll_reset
    # Honour the same invariant the report block below documents: never idle out
    # from under an accumulating burst. If the cap has passed while gh is
    # unreachable, report what was already observed rather than spinning — the
    # burst is real even though it can't be confirmed quiet.
    # `holding_draft` carries the last successful tick's value, which is the right
    # one to trust when gh cannot confirm draft status. Without it a held-back
    # draft reports COMMITS here — the case the quiet-period path already
    # excludes — and this is the laptop-sleep path, where the first poll after
    # wake can fail while `date` has already jumped past the cap.
    [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
      && [ "$(date +%s)" -ge "$settle_cap" ] && report_burst
    { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out \
      && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
    poll_nap; continue
  fi
  fails_primary=0

  # One shape gate for the payload, counted on its own. A parse failure here is
  # not a poll failure: `$J` came from a call that succeeded, so this is a
  # payload-shape change, which is never transient.
  #
  # It needs its own counter because the successful poll above resets
  # `fails_primary` on every iteration — sharing that counter caps a shape
  # failure at 1, so it can never reach FAIL_MAX and the watch idles out exactly
  # as it did when the parse was swallowed with `|| echo 0`.
  #
  # Guarded, not bare: an unguarded assignment dies under `set -e` with no
  # `result=` line at all, which is the same blindness in a louder costume.
  if STATE=$(echo "$J" | jq -r '.state // empty' 2>/dev/null); then
    fails_shape=0
  else
    fails_shape=$(( fails_shape + 1 ))
    [ "$fails_shape" -ge "$FAIL_MAX" ] \
      && report_error "$([ "$ISSUE_MODE" = 1 ] && echo issue-view-shape || echo pr-view-shape)"
    poll_reset
    { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out \
      && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
    poll_nap; continue
  fi

  # Issue mode ends here: nothing to settle, no drafts, no head SHA. Wake as soon
  # as a linked PR exists or the issue closes; otherwise fall through to the same
  # curve, failure counting and idle-out as the PR path.
  if [ "$ISSUE_MODE" = 1 ]; then
    if [ "$STATE" = CLOSED ]; then echo "result=CLOSED state=CLOSED"; exit 0; fi
    # Lowercase deliberately. An assignment to a name the caller already exported
    # updates the *exported* value, so a generic uppercase internal here would
    # clobber a caller's environment variable — and this script's children are
    # `gh` invocations that read the environment.
    # `// []` rather than a second guard: the shape gate above already proved the
    # payload parses, so a missing or null field is the only realistic gap left
    # here, and it reads as zero linked PRs — correct.
    #
    # Not total in general: `//` substitutes only on null or false, so a
    # wrong-typed field (`true`, a number, a string) still errors or miscounts.
    # Left unguarded deliberately — reaching it needs well-formed JSON carrying a
    # schema-valid field of the wrong type, while every realistic corruption
    # (an HTML error page, a truncated body, empty output) is caught by the gate.
    linked_n=$(echo "$J" | jq '(.closedByPullRequestsReferences // []) | length')
    if [ "${linked_n:-0}" -gt 0 ]; then
      echo "result=ACTIVITY activity=1 now=$(poll_now_iso)"; exit 0
    fi
    poll_timed_out && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
    poll_nap; continue
  fi
  if [ "$STATE" = MERGED ] || [ "$STATE" = CLOSED ]; then
    echo "result=CLOSED state=$STATE"; exit 0
  fi

  # NOT `.isDraft // empty`: jq's `//` treats `false` as absent, so the
  # alternative would fire exactly when the PR is ready, and the check below
  # could never match.
  DRAFT=$(echo "$J" | jq -r '.isDraft')
  HEAD=$(echo "$J" | jq -r '.headRefOid // empty')

  # New formal reviews / top-level comments after SINCE, not authored by the bot.
  # `[]?` skips a missing or non-array field, so the shape gate above is the only
  # place a payload change needs counting in practice. It guards the *iteration*,
  # not the elements: `reviews: [1,2]` would still error on `.submittedAt`. Same
  # judgement as the linked-PR count above — unreachable without well-formed JSON
  # of the wrong shape, and not worth a guard the gate already covers.
  NEW=$(echo "$J" | jq --arg s "$SINCE" --arg slug "$SLUG" '
    def mine: . == $slug or . == ($slug + "[bot]");
    [ (.reviews[]?  | select(.submittedAt > $s and (.author.login | mine | not))),
      (.comments[]? | select(.createdAt  > $s and (.author.login | mine | not))) ] | length')
  # New inline review-comments (thread replies) after SINCE, not by the bot.
  # Split the fetch from the parse so a failure is not read as "no new replies".
  # It previously ended in `|| echo 0`, which made this path fail *closed and
  # silent*: `gh pr view` keeps succeeding, so the watch looks healthy while
  # thread replies never register — partial blindness nothing reported.
  if RAWC=$(gh api "repos/$REPO/pulls/$PR/comments" 2>/dev/null); then
    if NEWC=$(echo "$RAWC" | jq --arg s "$SINCE" --arg slug "$SLUG" '
        def mine: . == $slug or . == ($slug + "[bot]");
        [ .[] | select(.created_at > $s and (.user.login | mine | not)) ] | length' 2>/dev/null)
    then fails_comments=0
    else
      # A jq failure here is a payload-shape change, never transient — the same
      # reason git-workflow's merge watcher deliberately leaves its jq unsilenced.
      fails_comments=$(( fails_comments + 1 )); NEWC="$obs_newc"
    fi
  else
    fails_comments=$(( fails_comments + 1 )); NEWC="$obs_newc"
  fi
  if [ "$fails_comments" -ge "$FAIL_MAX" ]; then report_error comments; fi
  [ "$fails_comments" -gt 0 ] && poll_reset

  # Accumulate this tick's deltas, and restart the quiet timer on anything new.
  changed=0
  if [ -n "$HEAD" ] && [ -n "$obs_head" ] && [ "$HEAD" != "$obs_head" ]; then
    saw_commits=1; new_head="$HEAD"; obs_head="$HEAD"; changed=1
  fi
  if [ "${NEW:-0}" -gt "$obs_new" ];   then saw_activity=1; obs_new="$NEW";   changed=1; fi
  if [ "${NEWC:-0}" -gt "$obs_newc" ]; then saw_activity=1; obs_newc="$NEWC"; changed=1; fi

  # Draft -> ready. Marking a PR ready is neither a push nor a review nor a
  # comment, so without this the transition is invisible and a deliberately
  # skipped draft would only be noticed on its next push — or never. Pass
  # `--was-draft` when arming the watch on a PR being skipped for that reason.
  #
  # Reported immediately rather than settled: a draft going ready is the signal to
  # start a first review, and nothing else in the burst changes that.
  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = false ]; then
    echo "result=READY new_head=$HEAD activity=$saw_activity now=$(poll_now_iso)"; exit 0
  fi

  # A draft we are deliberately holding back is not reportable. Without this a
  # push returns COMMITS, which routes the reviewer into Re-reviewing — reviewing
  # the very draft "Don't review a discovered PR that is still a draft" excludes.
  # Keep accumulating; the READY check above is what releases the burst.
  holding_draft=0
  [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = true ] && holding_draft=1

  if [ "$changed" = 1 ]; then
    # Reset-on-change also keeps SETTLE's resolution usable: the quiet-period
    # check runs once per tick, so a backed-off interval would let SETTLE_MAX
    # release bursts that should have settled quietly.
    #
    # It returns to the floor on each change, not for the whole burst — the quiet
    # tail still advances, so from a 10s floor a SETTLE=45 window releases nearer
    # 70s. SETTLE is a lower bound, so that is late rather than wrong.
    poll_reset
    NOW=$(date +%s)
    settle_until=$(( NOW + SETTLE ))
    [ "$settle_cap" = 0 ] && settle_cap=$(( NOW + SETTLE_MAX ))
  fi

  # Report once the burst has been quiet for SETTLE, or the cap forces it.
  if [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
     && { [ "$(date +%s)" -ge "$settle_until" ] || [ "$(date +%s)" -ge "$settle_cap" ]; }; then
    report_burst
  fi

  # Idle out only when nothing is being withheld — either nothing is mid-settle,
  # or a burst is accumulating behind a held-back draft, which has no release
  # short of the draft going ready and would otherwise never time out.
  { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out \
    && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
  # No poll_reset on a quiet tick: the curve is a function of how long it has
  # been since something happened, so quiet is exactly what widens it.
  poll_nap
done
