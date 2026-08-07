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
#
# `activity=1` on a COMMITS or READY result means comments or replies landed in
# the same burst. The primary result names what to do first; the flag says there
# is also unread conversation. Ignoring it loses those replies for good, because
# the agent re-arms with since_iso set to now.
#
# Reads with the dev's own gh auth (not the 1-hour bot token) so a long watch —
# including across laptop sleep — doesn't expire its credential mid-poll.
set -euo pipefail
unset GH_TOKEN   # use the dev's own (non-expiring) gh auth for the long poll

REPO="${1:?owner/repo}"; PR="${2:?pr number}"
LAST_HEAD="${3:-}"; SINCE="${4:-1970-01-01T00:00:00Z}"; SLUG="${5:-}"
WAS_DRAFT=0; [ "${6:-}" = "--was-draft" ] && WAS_DRAFT=1
INTERVAL=${INTERVAL:-30}   # overridable so the settle logic can be exercised without minute-long waits
# 6h window. Unlike git-workflow's review/merge watchers (where a timeout means
# "something's wrong — wake once, don't re-spawn"), IDLE here is normal: a quiet
# PR is expected, so the agent simply re-arms. The window only bounds runaway and
# refreshes the poll after a long sleep.
deadline=$(( $(date +%s) + 21600 ))

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
SETTLE=${SETTLE:-45}
SETTLE_MAX=${SETTLE_MAX:-300}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
timed_out() { [ "$(date +%s)" -ge "$deadline" ]; }

# What the burst contained. `obs_*` track the last values already accounted for,
# so a *second* push or reply during the window registers as new and extends it
# rather than re-reporting the same one forever.
saw_commits=0; saw_activity=0; new_head=""
obs_head="$LAST_HEAD"; obs_new=0; obs_newc=0
settle_until=0; settle_cap=0

# Each jq program defines `mine` (true if a login is the bot, in either API's
# form). $slug/$s are jq vars from --arg, so the program stays single-quoted.

while :; do
  # Tolerate transient gh/network failures — skip the tick rather than dying
  # (set -e would otherwise kill the watch on a blip; an empty value must not
  # be read as a change).
  if ! J=$(gh pr view "$PR" --repo "$REPO" --json state,isDraft,headRefOid,reviews,comments 2>/dev/null); then
    timed_out && { echo "result=IDLE now=$(now_iso)"; exit 0; }
    sleep "$INTERVAL"; continue
  fi

  STATE=$(echo "$J" | jq -r '.state // empty')
  if [ "$STATE" = MERGED ] || [ "$STATE" = CLOSED ]; then
    echo "result=CLOSED state=$STATE"; exit 0
  fi

  # NOT `.isDraft // empty`: jq's `//` treats `false` as absent, so the
  # alternative would fire exactly when the PR is ready, and the check below
  # could never match.
  DRAFT=$(echo "$J" | jq -r '.isDraft')
  HEAD=$(echo "$J" | jq -r '.headRefOid // empty')

  # New formal reviews / top-level comments after SINCE, not authored by the bot.
  NEW=$(echo "$J" | jq --arg s "$SINCE" --arg slug "$SLUG" '
    def mine: . == $slug or . == ($slug + "[bot]");
    [ (.reviews[]?  | select(.submittedAt > $s and (.author.login | mine | not))),
      (.comments[]? | select(.createdAt  > $s and (.author.login | mine | not))) ] | length' 2>/dev/null || echo 0)
  # New inline review-comments (thread replies) after SINCE, not by the bot.
  NEWC=$(gh api "repos/$REPO/pulls/$PR/comments" 2>/dev/null \
    | jq --arg s "$SINCE" --arg slug "$SLUG" '
        def mine: . == $slug or . == ($slug + "[bot]");
        [ .[] | select(.created_at > $s and (.user.login | mine | not)) ] | length' 2>/dev/null || echo 0)

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
    echo "result=READY new_head=$HEAD activity=$saw_activity now=$(now_iso)"; exit 0
  fi

  if [ "$changed" = 1 ]; then
    NOW=$(date +%s)
    settle_until=$(( NOW + SETTLE ))
    [ "$settle_cap" = 0 ] && settle_cap=$(( NOW + SETTLE_MAX ))
  fi

  # Report once the burst has been quiet for SETTLE, or the cap forces it.
  if [ "$settle_until" != 0 ] \
     && { [ "$(date +%s)" -ge "$settle_until" ] || [ "$(date +%s)" -ge "$settle_cap" ]; }; then
    if [ "$saw_commits" = 1 ]; then
      echo "result=COMMITS new_head=$new_head activity=$saw_activity now=$(now_iso)"
    else
      echo "result=ACTIVITY activity=1 now=$(now_iso)"
    fi
    exit 0
  fi

  # Only idle out when nothing is mid-settle; otherwise the burst would be
  # discarded at the deadline having never been reported.
  [ "$settle_until" = 0 ] && timed_out && { echo "result=IDLE now=$(now_iso)"; exit 0; }
  sleep "$INTERVAL"
done
