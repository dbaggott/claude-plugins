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
#   result=COMMITS new_head=<sha> now=<iso>   # author pushed new commits
#   result=ACTIVITY now=<iso>                 # new review/comment/reply, not the bot's
#   result=READY new_head=<sha> now=<iso>     # draft marked ready — only with --was-draft
#   result=CLOSED state=MERGED|CLOSED         # PR finished — stop watching
#   result=IDLE now=<iso>                     # nothing within the window — re-arm
#
# Reads with the dev's own gh auth (not the 1-hour bot token) so a long watch —
# including across laptop sleep — doesn't expire its credential mid-poll.
set -euo pipefail
unset GH_TOKEN   # use the dev's own (non-expiring) gh auth for the long poll

REPO="${1:?owner/repo}"; PR="${2:?pr number}"
LAST_HEAD="${3:-}"; SINCE="${4:-1970-01-01T00:00:00Z}"; SLUG="${5:-}"
WAS_DRAFT=0; [ "${6:-}" = "--was-draft" ] && WAS_DRAFT=1
INTERVAL=30
# 6h window. Unlike git-workflow's review/merge watchers (where a timeout means
# "something's wrong — wake once, don't re-spawn"), IDLE here is normal: a quiet
# PR is expected, so the agent simply re-arms. The window only bounds runaway and
# refreshes the poll after a long sleep.
deadline=$(( $(date +%s) + 21600 ))

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
timed_out() { [ "$(date +%s)" -ge "$deadline" ]; }

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

  # Draft -> ready. Marking a PR ready is neither a push nor a review nor a
  # comment, so without this the transition is invisible and a deliberately
  # skipped draft would only be noticed on its next push — or never. Pass
  # `--was-draft` when arming the watch on a PR being skipped for that reason.
  # NOT `.isDraft // empty`: jq's `//` treats `false` as absent, so the alternative
  # fires exactly when the PR is ready and the check could never match.
  DRAFT=$(echo "$J" | jq -r '.isDraft')
  HEAD=$(echo "$J" | jq -r '.headRefOid // empty')
  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = false ]; then
    echo "result=READY new_head=$HEAD now=$(now_iso)"; exit 0
  fi

  if [ -n "$HEAD" ] && [ -n "$LAST_HEAD" ] && [ "$HEAD" != "$LAST_HEAD" ]; then
    echo "result=COMMITS new_head=$HEAD now=$(now_iso)"; exit 0
  fi

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

  if [ "${NEW:-0}" -gt 0 ] || [ "${NEWC:-0}" -gt 0 ]; then
    echo "result=ACTIVITY now=$(now_iso)"; exit 0
  fi

  timed_out && { echo "result=IDLE now=$(now_iso)"; exit 0; }
  sleep "$INTERVAL"
done
