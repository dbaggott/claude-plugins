#!/usr/bin/env bash
# Block until something a caller should act on happens to a pull request, print
# what it was, and exit. Spawned as a background task; when it returns, the
# caller acts and re-arms with the line this prints.
#
#   watch-pr.sh <owner/repo> <pr> [<last_head>] [<since>] [<slug>] \
#     [--role=author|reviewer] [--was-draft] [--last-verdict=<sha>] [--last-checks=<names>]
#
# Exactly one result line, then exit 0:
#   result=COMMITS  new_head=<sha> activity=0|1 now=<iso>   # someone pushed
#   result=ACTIVITY activity=1 now=<iso>                    # review/comment/reply, not the caller's
#   result=CHECKS   checks=<names> now=<iso>                # a check on this head stopped passing
#   result=READY    new_head=<sha> activity=0|1 now=<iso>   # draft marked ready — only with --was-draft
#   result=DIRTY    now=<iso>                               # conflict with base — author role only
#   result=BLOCKED  cause=terminal now=<iso>                # still blocked, nothing pending — author only
#   result=CLOSED   state=MERGED|CLOSED                     # finished — stop watching
#   result=IDLE     now=<iso>                               # nothing within the window
#   result=ERROR    reason=<source> now=<iso>               # the watch is broken — do NOT re-arm
#
# Every result a caller re-arms from is preceded by a `── re-arm ──` line
# carrying the next invocation; a burst also carries `── next ──`, the
# pr-round.sh call that reads it in full. CLOSED and ERROR carry neither.
#
# WHAT --role CHANGES, since it is not a label. An author and a reviewer want
# mirror images of each other from one PR, and taking it as an argument is what
# removes the caller's choice of which watcher to run:
#
#   author    waits for a verdict. Its own pushes are not news, so COMMITS is not
#             a wake. It owns the merge, so DIRTY and a terminal BLOCKED are.
#             Ignores the operator's login. Shorter window — quiet here is suspect.
#   reviewer  waits for a push. COMMITS is the wake; merge state is not its
#             business. Ignores the bot's login. Longer window — quiet is normal.
#
# ⚠️ THE SLUG IS WHOSE ACTIVITY TO IGNORE, AND THE TWO ROLES IGNORE DIFFERENT
# PEOPLE. Defaulting it without a role hands a reviewer watch the operator's
# login, which excludes the wrong identity and leaves the watch waking on its own
# posts. An empty slug excludes nobody — the same failure with no argument to
# blame — so it is refused.
set -euo pipefail
unset GH_TOKEN   # use the dev's own (non-expiring) gh auth for the long poll

_poll_argv="$*"

REPO=""; PR=""; LAST_HEAD=""; SINCE=""; SLUG=""
ROLE=""; WAS_DRAFT=0; LAST_VERDICT=""; LAST_CHECKS=""
bad=0; pos=0
for arg in "$@"; do
  case "$arg" in
    --role=*)         ROLE="${arg#--role=}" ;;
    --was-draft)      WAS_DRAFT=1 ;;
    --last-verdict=*) LAST_VERDICT="${arg#--last-verdict=}" ;;
    --last-checks=*)  LAST_CHECKS="${arg#--last-checks=}" ;;
    --*)              bad=1 ;;
    *) pos=$(( pos + 1 ))
       case $pos in
         1) REPO="$arg" ;; 2) PR="$arg" ;; 3) LAST_HEAD="$arg" ;;
         4) SINCE="$arg" ;; 5) SLUG="$arg" ;; *) bad=1 ;;
       esac ;;
  esac
done

# shellcheck source=./lib-poll.sh
. "$(dirname "$0")/lib-poll.sh"
# shellcheck source=./lib-watch.sh
. "$(dirname "$0")/lib-watch.sh"
# shellcheck source=./lib-activity.sh
. "$(dirname "$0")/lib-activity.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
fatal() { echo "result=ERROR reason=$1 now=$(poll_now_iso)"; exit 0; }

# Enumerated rather than a range: bracket ranges match in collation order, which
# under bash 3.2 in a UTF-8 locale interleaves case, so `a-f` would span
# `a A b B …` and the uppercase rejection would become a silent no-op on stock
# macOS while passing on CI.
sha_ok() {
  case $1 in
    '') return 0 ;;
    *[!0123456789abcdef]*) return 1 ;;
    *) [ "${#1}" = 40 ] ;;
  esac
}

case "$ROLE" in author|reviewer) ;; *) bad=1 ;; esac
[ -n "$REPO" ] && [ -n "$PR" ] || bad=1
case "$PR" in ''|*[!0-9]*) bad=1 ;; esac
sha_ok "$LAST_HEAD" || bad=1
sha_ok "$LAST_VERDICT" || bad=1
[ -n "$SINCE" ] || SINCE="1970-01-01T00:00:00Z"

# Only the author's own login is derivable here. A reviewer's is its bot's,
# which only the reviewer config knows, so that role has to be told.
if [ -z "$SLUG" ] && [ "$ROLE" = author ]; then
  SLUG=$(gh api user --jq .login 2>/dev/null) || SLUG=""
fi
[ -n "$SLUG" ] || bad=1

# A result line rather than a die: callers read a MISSING one as "the task was
# killed, re-read HEAD", so exiting silently would make a typo present as the
# vanished watch the tracing exists to keep legible.
[ "$bad" = 1 ] && fatal bad-args

WINDOW=${WINDOW:-$([ "$ROLE" = author ] && echo 1800 || echo 21600)}

# Sized for an author's round, which is a burst — reply to three threads, then
# push the fix. A reviewer's round is one write, needing only enough to cover
# skew between sources.
SETTLE=${SETTLE:-45}
SETTLE_MAX=${SETTLE_MAX:-300}

poll_init

saw_commits=0; saw_activity=0; saw_ready=0
new_head=""; verdict_sha=""; verdict_state=""; checks_now=""
obs_head="$LAST_HEAD"; obs_new=0; obs_newc=0
settle_until=0; settle_cap=0; holding_draft=0
J=""; RAWC="[]"

rearm_cmd() {
  printf '"%s/watch-pr.sh" %s %s %s %s %s --role=%s%s --last-verdict=%s --last-checks=%s' \
    "$HERE" "$REPO" "$PR" "${new_head:-${obs_head:-\"\"}}" "$(poll_now_iso)" "$SLUG" "$ROLE" \
    "$([ "$WAS_DRAFT" = 1 ] && [ "$saw_ready" = 0 ] && printf ' --was-draft' || true)" \
    "${verdict_sha:-$LAST_VERDICT}" "${checks_now:-$LAST_CHECKS}"
}

emit_activity() {
  [ "$saw_activity" = 1 ] || return 0
  { printf '%s' "${J:-}"     | jq -c --arg s "$SINCE" --arg slug "$SLUG" "$ACTIVITY_JQ_REVIEWS" 2>/dev/null || true
    printf '%s' "${RAWC:-}"  | jq -c --arg s "$SINCE" --arg slug "$SLUG" "$ACTIVITY_JQ_INLINE"  2>/dev/null || true
  } | jq -c "$ACTIVITY_JQ_SUMMARY" 2>/dev/null || true
}

emit_next() {
  printf '── next ──\n'
  printf '"%s/pr-round.sh" %s %s %s %s %s\n' \
    "$HERE" "$REPO" "$PR" "${LAST_HEAD:-\"\"}" "$SINCE" "$SLUG"
}

verdict_field() {
  [ -n "$verdict_sha" ] && printf ' verdict_sha=%s verdict=%s' "$verdict_sha" "$verdict_state" || true
}

report_idle() { watch_rearm "$(rearm_cmd)"; echo "result=IDLE now=$(poll_now_iso)"; exit 0; }

# A burst in hand outranks ERROR: the activity is real, and reporting ERROR
# instead sends the caller to re-arm straight back into the failure having
# silently dropped what was already seen.
report_error() {
  [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] && report_burst
  echo "result=ERROR reason=$1 now=$(poll_now_iso)"
  exit 0
}

report_burst() {
  emit_activity
  emit_next
  watch_rearm "$(rearm_cmd)"
  if [ "$saw_ready" = 1 ]; then
    echo "result=READY new_head=$new_head activity=$saw_activity$(verdict_field) now=$(poll_now_iso)"
  elif [ "$saw_commits" = 1 ]; then
    echo "result=COMMITS new_head=$new_head activity=$saw_activity$(verdict_field) now=$(poll_now_iso)"
  else
    echo "result=ACTIVITY activity=1$(verdict_field) now=$(poll_now_iso)"
  fi
  exit 0
}

report_now() {  # <result> [extra]
  watch_rearm "$(rearm_cmd)"
  echo "result=$1${2:+ $2} now=$(poll_now_iso)"
  exit 0
}

while :; do
  OUT=$("$HERE/fetch-pr-state.sh" "$REPO" "$PR" 2>/dev/null) || OUT=""
  LINE=$(printf '%s\n' "$OUT" | tail -1)
  J=$(printf '%s\n' "$OUT" | sed '$d')

  ok=0
  case "$LINE" in
    result=OK*)
      ok=1; watch_ok pr-view
      case "$LINE" in
        *degraded=inline-comments*) watch_fail inline-comments report_error ;;
        *)                          watch_ok inline-comments ;;
      esac ;;
    *reason=pr-view-shape*) watch_fail_shape pr-view report_error ;;
    *reason=bad-args*|*reason=unsupported-forge*) fatal "${LINE#*reason=}" ;;
    *reason=*)              watch_fail "$(printf '%s' "$LINE" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')" report_error ;;
    *)                      watch_fail pr-view report_error ;;
  esac

  if [ "$ok" = 0 ]; then
    poll_reset
    [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
      && [ "$(date +%s)" -ge "$settle_cap" ] && report_burst
    { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out && report_idle
    poll_nap; continue
  fi

  STATE=$(printf '%s' "$J" | jq -r '.state')
  DRAFT=$(printf '%s' "$J" | jq -r '.draft')
  HEAD=$(printf '%s' "$J" | jq -r '.head')
  RAWC=$(printf '%s' "$J" | jq -c '.inline')

  if [ "$STATE" = MERGED ] || [ "$STATE" = CLOSED ]; then
    echo "result=CLOSED state=$STATE"; exit 0
  fi

  # Merge state is the author's business — they own the merge. A reviewer
  # watching the same PR has nothing to do about a conflict with base.
  if [ "$ROLE" = author ] && [ "$settle_until" = 0 ]; then
    MSTATUS=$(printf '%s' "$J" | jq -r '.merge.status')
    MCAUSE=$(printf '%s' "$J" | jq -r '.merge.cause // ""')
    [ "$MSTATUS" = dirty ] && report_now DIRTY
    if [ "$MSTATUS" = blocked ] && [ "$MCAUSE" = terminal ]; then
      report_now BLOCKED "cause=terminal"
    fi
  fi

  [ -z "$obs_head" ] && [ -n "$HEAD" ] && obs_head="$HEAD"

  # Level-triggered, like the verdict: a conclusion is current state, so counting
  # it as an event wakes on one red build forever, and filtering it by `since`
  # loses one that landed while no watch was running.
  checks_now=$(printf '%s' "$J" | jq -r '
    [ .checks[] | select(.state != "success" and .state != "neutral" and .state != "pending")
      | .name ] | sort | join(",")')
  if [ -n "$checks_now" ] && [ "$checks_now" != "$LAST_CHECKS" ] && [ "$settle_until" = 0 ]; then
    report_now CHECKS "checks=$checks_now"
  fi

  new_reviews=$(printf '%s' "$J" | jq -r --arg s "$SINCE" --arg slug "$SLUG" '
    [ (.reviews[]?, .comments[]?)
      | select(.at > $s)
      | select(.author != $slug and .author != ($slug + "[bot]")) ] | length')
  new_inline=$(printf '%s' "$J" | jq -r --arg s "$SINCE" --arg slug "$SLUG" '
    [ .inline[]? | select(.at > $s)
      | select(.author != $slug and .author != ($slug + "[bot]")) ] | length')

  verdict_line=$(printf '%s' "$J" | jq -r --arg head "$HEAD" --arg slug "$SLUG" '
    [ .reviews[]?
      | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")
      | select(.author != $slug and .author != ($slug + "[bot]")) ]
    | (last // {}) | select((.sha // "") == $head) | "\(.sha) \(.state)"' 2>/dev/null || true)

  changed=0
  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = false ] && [ "$saw_ready" = 0 ]; then
    saw_ready=1; new_head="$HEAD"; changed=1
  fi
  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = true ]; then holding_draft=1; else holding_draft=0; fi

  if [ -n "$HEAD" ] && [ "$HEAD" != "$obs_head" ]; then
    # An author's own push is not news to the author.
    if [ "$ROLE" = reviewer ]; then saw_commits=1; changed=1; fi
    new_head="$HEAD"; obs_head="$HEAD"
  fi
  if [ "$new_reviews" -gt "$obs_new" ] || [ "$new_inline" -gt "$obs_newc" ]; then
    saw_activity=1; changed=1; obs_new="$new_reviews"; obs_newc="$new_inline"
  fi
  if [ -n "$verdict_line" ]; then
    vsha="${verdict_line%% *}"
    if [ "$vsha" != "$LAST_VERDICT" ]; then
      verdict_sha="$vsha"; verdict_state="${verdict_line#* }"; changed=1
    fi
  fi

  if [ "$changed" = 1 ]; then
    poll_reset
    [ "$settle_until" = 0 ] && settle_cap=$(( $(date +%s) + SETTLE_MAX ))
    settle_until=$(( $(date +%s) + SETTLE ))
  fi

  if [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
     && { [ "$(date +%s)" -ge "$settle_until" ] || [ "$(date +%s)" -ge "$settle_cap" ]; }; then
    report_burst
  fi

  { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out && report_idle
  poll_nap
done
