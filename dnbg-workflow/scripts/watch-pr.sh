#!/usr/bin/env bash
# Block until something a caller should act on happens to a pull request, print
# what it was, and exit. Spawned as a background task; when it returns, the
# caller acts and re-arms with the line this prints.
#
#   watch-pr.sh <owner/repo> <pr> [<last_head>] [<since>] [<slug>] \
#     --role=author|reviewer [--was-draft] [--last-verdict=<sha>] \
#     [--last-checks=<names>] [--merge-stage]
#
# Exactly one result line, then exit 0:
#   result=COMMITS  new_head=<sha> activity=0|1 now=<iso>   # someone pushed
#   result=ACTIVITY activity=1 now=<iso>                    # review/comment/reply, not the caller's
#   result=CHECKS   checks='<names>' now=<iso>              # only a check stopped passing
#
# Any burst also carries `checks='<names>'` when a check on the head is failing,
# so a wake that is primarily something else still says the build is red. The
# set is level-triggered: `--last-checks` is what the caller has been TOLD is
# failing, which a recovery clears and an unreported failure does not advance.
# The value is shell-quoted in both places — forge check names contain spaces.
#   result=READY    new_head=<sha> activity=0|1 now=<iso>   # draft marked ready — only with --was-draft
#   result=DIRTY    now=<iso>                               # conflict with base — author role only
#   result=BLOCKED  cause=terminal now=<iso>                # nothing pending will clear it
#                                                           # — author role WITH --merge-stage only
#   result=CLOSED   state=MERGED|CLOSED                     # finished — stop watching
#   result=IDLE     [merge=behind|blocked|unrecognised:<v>] now=<iso>
#   result=ERROR    reason=<source> now=<iso>               # the watch is broken — do NOT re-arm
#
# Every result a caller re-arms from is preceded by a `── re-arm ──` line
# carrying the next invocation; a burst also carries `── next ──`, the
# pr-round.sh call that reads it in full. CLOSED, ERROR, DIRTY and BLOCKED carry
# neither — none of the four clears without a human, so a re-armed watch would
# report the same state on its next tick for as long as it kept being re-armed.
#
# WHAT --role CHANGES, since it is not a label. An author and a reviewer want
# mirror images of each other from one PR, and taking it as an argument is what
# removes the caller's choice of which watcher to run:
#
#   author    waits for a verdict. Its own pushes are not news, so COMMITS is not
#             a wake. It owns the merge, so DIRTY is. Ignores the operator's
#             login. Shorter window — quiet here is suspect.
#
# --merge-stage says the review is over and the wait is now for the merge, which
# is the only point at which a terminal block is worth stopping for. Before it,
# a blocked PR is the ordinary state of one under review.
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
ROLE=""; WAS_DRAFT=0; LAST_VERDICT=""; LAST_CHECKS=""; MERGE_STAGE=0
bad=0; pos=0
for arg in "$@"; do
  case "$arg" in
    --role=*)         ROLE="${arg#--role=}" ;;
    --was-draft)      WAS_DRAFT=1 ;;
    --last-verdict=*) LAST_VERDICT="${arg#--last-verdict=}" ;;
    --last-checks=*)  LAST_CHECKS="${arg#--last-checks=}" ;;
    --merge-stage)    MERGE_STAGE=1 ;;
    --*)              bad=1 ;;
    *) pos=$(( pos + 1 ))
       case $pos in
         1) REPO="$arg" ;; 2) PR="$arg" ;; 3) LAST_HEAD="$arg" ;;
         4) SINCE="$arg" ;; 5) SLUG="$arg" ;; *) bad=1 ;;
       esac ;;
  esac
done

# Before lib-poll.sh, which applies its own `WINDOW` default the moment it is
# sourced — set after, this never fires and both roles silently get the long one.
WINDOW=${WINDOW:-$([ "$ROLE" = author ] && echo 1800 || echo 21600)}

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

# Sized for an author's round, which is a burst — reply to three threads, then
# push the fix. A reviewer's round is one write, needing only enough to cover
# skew between sources.
SETTLE=${SETTLE:-45}
SETTLE_MAX=${SETTLE_MAX:-300}

poll_init

saw_commits=0; saw_activity=0; saw_ready=0; saw_checks=""
new_head=""; verdict_sha=""; verdict_state=""; checks_now=""
# What the caller has been told is failing. Not simply the latest reading: a
# recovery has to clear it or the same check failing twice is reported once, and
# a failure seen but held back by a settle must not advance it or the caller is
# told it was handled when it was never reported.
checks_baseline="$LAST_CHECKS"
last_json=""
obs_head="$LAST_HEAD"; obs_new=0; obs_newc=0; obs_verdict=""
# What the caller has HANDLED, which only a report advances — as against
# `obs_head`, what this run has SEEN, which stops it re-detecting one move every
# tick. Sharing them advances the head past a push the author role never
# reported, and the next round's diff then starts after that commit: it appears
# in none of them.
rearm_head="$LAST_HEAD"
settle_until=0; settle_cap=0; holding_draft=0; stop_merge=""; idle_merge=""
J=""; RAWC="[]"

# A check name is forge-supplied and routinely contains a space — `build
# (macos-latest)` is what a default matrix job is called — so anywhere a name is
# printed it is quoted. Unquoted, the re-arm line is a syntax error rather than a
# command, and a result line splits into fields nobody can parse.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# `WINDOW=` is carried because the line's whole contract is that running it
# continues THIS watch. merge.md arms a six-hour wait explicitly, and a bare
# command silently drops it back to the role default on the first wake — after
# which the skill reports a thirty-minute idle as six hours with no merge.
#
# `${3-}` rather than `${3:-}` on the verdict: empty is a deliberate value there
# ("no verdict handled yet"), so `:-` would substitute the mutated state back in
# and mark a verdict handled that no run ever reported.
rearm_cmd() {  # [head] [since] [verdict]
  printf 'WINDOW=%s "%s/watch-pr.sh" %s %s %s %s %s --role=%s%s --last-verdict=%s --last-checks=%s' \
    "$WINDOW" "$HERE" "$REPO" "$PR" "${1:-${rearm_head:-\"\"}}" "${2:-$(poll_now_iso)}" \
    "$SLUG" "$ROLE" \
    "$([ "$WAS_DRAFT" = 1 ] && [ "$saw_ready" = 0 ] && printf ' --was-draft' || true)$([ "$MERGE_STAGE" = 1 ] && printf ' --merge-stage' || true)" \
    "${3-${verdict_sha:-$LAST_VERDICT}}" "$(shq "$checks_baseline")"
}

# The arguments this run STARTED with. A run that reports nothing has handled
# nothing, so that is what it must hand back — advancing `since` past activity it
# is still holding deletes that activity rather than deferring it.
ORIG_HEAD="${LAST_HEAD:-\"\"}"; ORIG_SINCE="$SINCE"; ORIG_VERDICT="$LAST_VERDICT"

emit_activity() {
  [ "$saw_activity" = 1 ] || return 0
  { printf '%s' "${last_json:-}" | jq -c --arg s "$SINCE" --arg slug "$SLUG" "$ACTIVITY_JQ_REVIEWS" 2>/dev/null || true
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

# IDLE is reachable with a burst still held: the draft hold gates the release but
# not the window. Nothing was reported, so the re-arm hands back the state this
# run was given — the hold survives, and the next run re-observes what this one
# saw instead of it being filtered out by an advanced `since`.
report_idle() {
  if have_burst; then
    watch_rearm "$(rearm_cmd "$ORIG_HEAD" "$ORIG_SINCE" "$ORIG_VERDICT")"
  else
    watch_rearm "$(rearm_cmd)"
  fi
  echo "result=IDLE${idle_merge:+ merge=$idle_merge} now=$(poll_now_iso)"; exit 0
}

# Whether anything is still worth waking the caller for. A settle can outlive its
# own reason — a red check that goes green again while the window holds — and
# reporting an empty burst emits a bare `ACTIVITY activity=1` for activity that
# never happened. One entry per thing that starts a settle; a verdict counts,
# since a verdict standing at HEAD is a wake on its own with no flag set.
have_burst() {
  [ "$saw_ready" = 1 ] || [ "$saw_commits" = 1 ] || [ "$saw_activity" = 1 ] \
    || [ -n "$saw_checks" ] || [ -n "$verdict_sha" ]
}

# A burst in hand outranks ERROR: the activity is real, and reporting ERROR
# instead sends the caller to re-arm straight back into the failure having
# silently dropped what was already seen.
report_error() {
  if [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] && have_burst; then
    report_burst
  fi
  echo "result=ERROR reason=$1 now=$(poll_now_iso)"
  exit 0
}

report_burst() {
  local checks_only=0
  if [ -n "$saw_checks" ] && [ "$saw_ready" = 0 ] && [ "$saw_commits" = 0 ] \
     && [ "$saw_activity" = 0 ] && [ -z "$verdict_sha" ]; then checks_only=1; fi

  emit_activity
  # Withheld for a checks-only wake: `── next ──` is a four-request round over
  # the diff, the bodies and the threads, and both skills say a red build is
  # neither a re-review nor a finding to answer. Offering it there invites a
  # round they are then told not to spend.
  [ "$checks_only" = 0 ] && emit_next
  # `── next ──` hands the caller a diff spanning from the head this run was
  # armed with, so reporting is what makes every move up to now handled.
  rearm_head="$obs_head"
  [ -n "$saw_checks" ] && checks_baseline="$saw_checks"
  watch_rearm "$(rearm_cmd)"
  local ck="" mg=""
  [ -n "$saw_checks" ] && ck=" checks=$(shq "$saw_checks")"
  [ -n "$stop_merge" ] && mg=" merge=$stop_merge"
  # A verdict excludes this arm deliberately: CHECKS is documented as "not your
  # finding to fix, re-arm without acting", and the re-arm marks the verdict
  # handled — so reducing an unhandled verdict to CHECKS loses it until the IDLE
  # backstop notices an approval standing at HEAD, a window later.
  if [ "$checks_only" = 1 ]; then
    echo "result=CHECKS checks=$(shq "$saw_checks")$mg now=$(poll_now_iso)"
    exit 0
  fi
  if [ "$saw_ready" = 1 ]; then
    echo "result=READY new_head=$new_head activity=$saw_activity$ck$mg$(verdict_field) now=$(poll_now_iso)"
  elif [ "$saw_commits" = 1 ]; then
    echo "result=COMMITS new_head=$new_head activity=$saw_activity$ck$mg$(verdict_field) now=$(poll_now_iso)"
  else
    echo "result=ACTIVITY activity=$saw_activity$ck$mg$(verdict_field) now=$(poll_now_iso)"
  fi
  exit 0
}

# DIRTY and a terminal block carry no re-arm line, for the reason CLOSED and
# ERROR carry none: neither clears without a human, so a caller re-arming from
# one wakes on the same state every tick until someone intervenes.
report_stop() {  # <result> [extra]
  # Anything already in hand rides out first, carrying the block as a field. The
  # caller then re-arms from that line and gets the bare stop on the next tick,
  # so nothing is lost and the stop still happens.
  if have_burst; then stop_merge="$1"; report_burst; fi
  echo "result=$1${2:+ $2} now=$(poll_now_iso)"
  exit 0
}

while :; do
  OUT=$("$HERE/fetch-pr-state.sh" "$REPO" "$PR" 2>/dev/null) || OUT=""
  LINE=$(printf '%s\n' "$OUT" | tail -1)
  J=$(printf '%s\n' "$OUT" | sed '$d')
  [ -n "$J" ] && last_json="$J"

  ok=0
  case "$LINE" in
    result=OK*)
      ok=1; watch_ok pr-view
      case "$LINE" in
        *degraded=inline-comments*) watch_fail inline-comments report_error ;;
        *)                          watch_ok inline-comments ;;
      esac ;;
    *reason=pr-view-shape*) watch_fail_shape pr-view report_error ;;
    *reason=bad-args*|*reason=unsupported-forge*) fatal "$(r="${LINE#*reason=}"; printf %s "${r%% *}")" ;;
    *reason=*)              watch_fail "$(printf '%s' "$LINE" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')" report_error ;;
    *)                      watch_fail pr-view report_error ;;
  esac

  if [ "$ok" = 0 ]; then
    poll_reset
    if [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
       && [ "$(date +%s)" -ge "$settle_cap" ] && have_burst; then
      report_burst
    fi
    { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out && report_idle
    poll_nap; continue
  fi

  STATE=$(printf '%s' "$J" | jq -r '.state')
  DRAFT=$(printf '%s' "$J" | jq -r '.draft')
  HEAD=$(printf '%s' "$J" | jq -r '.head')
  # Guarded like `last_json`: a degraded tick carries `[]` for this half, and
  # overwriting on one empties the summary for a burst whose activity was inline
  # comments in the first place.
  case "$LINE" in
    *degraded=inline-comments*) ;;
    *) RAWC=$(printf '%s' "$J" | jq -c '.inline') ;;
  esac

  if [ "$STATE" = MERGED ] || [ "$STATE" = CLOSED ]; then
    echo "result=CLOSED state=$STATE"; exit 0
  fi

  [ -z "$obs_head" ] && [ -n "$HEAD" ] && obs_head="$HEAD"

  # Reset before the first thing that can set it, not after — the checks block
  # below sets it where the set moves.
  changed=0

  # Level-triggered, like the verdict: a conclusion is current state, so counting
  # it as an event wakes on one red build forever, and filtering it by `since`
  # loses one that landed while no watch was running.
  checks_now=$(printf '%s' "$J" | jq -r '
    [ .checks[] | select(.state == "failure") | .name ] | sort | join(",")')
  # Green clears the baseline; a failure only advances it once it has been
  # reported, which a settle in progress defers. Green also withdraws a failure
  # not yet reported — a check that recovers inside the settle it triggered is
  # not news, and reporting it names a red build the caller would find green.
  #
  # `changed` is set where the set MOVES, not while it is non-empty. A standing
  # failure is level state and stays set until it is reported, so charging it
  # every tick resets the backoff curve every tick — which on a draft hold, where
  # the burst is never released, pins the poll at the curve's floor for the whole
  # window.
  if [ -z "$checks_now" ]; then
    checks_baseline=""; saw_checks=""
  elif [ "$checks_now" = "$checks_baseline" ]; then
    # Exactly what the caller was already told is failing, so there is nothing
    # outstanding — including when a partial recovery brought the set back to it.
    # Keeping a stale name here reports a check they would find green, and then
    # advances the baseline onto a set that never existed.
    saw_checks=""
  else
    [ "$checks_now" != "$saw_checks" ] && changed=1
    saw_checks="$checks_now"
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
      | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")
      | select(.author != $slug and .author != ($slug + "[bot]")) ]
    | (last // {}) | select((.sha // "") == $head) | "\(.sha) \(.state)"')

  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = false ] && [ "$saw_ready" = 0 ]; then
    saw_ready=1; new_head="$HEAD"
  fi
  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = true ]; then holding_draft=1; else holding_draft=0; fi

  if [ -n "$HEAD" ] && [ "$HEAD" != "$obs_head" ]; then
    # An author's own push is not news to the author.
    if [ "$ROLE" = reviewer ]; then saw_commits=1; changed=1; new_head="$HEAD"; fi
    obs_head="$HEAD"
  fi
  if [ "$new_reviews" -gt "$obs_new" ] || [ "$new_inline" -gt "$obs_newc" ]; then
    saw_activity=1; changed=1; obs_new="$new_reviews"; obs_newc="$new_inline"
  fi
  if [ -n "$verdict_line" ]; then
    vsha="${verdict_line%% *}"
    # Two different facts, so two variables. `obs_verdict` stops one standing
    # verdict from re-triggering the settle on every tick; `LAST_VERDICT` is what
    # the CALLER has handled, and only a report may advance it. Sharing one hands
    # back a verdict no run reported, which suppresses it if the head ever
    # returns to that SHA.
    if [ "$vsha" != "$LAST_VERDICT" ] && [ "$vsha" != "$obs_verdict" ]; then
      verdict_sha="$vsha"; verdict_state="${verdict_line#* }"; changed=1
      obs_verdict="$vsha"
    fi
  else
    # No verdict stands at the current head — a push moved past the one seen
    # earlier in this run. The field means "a verdict stands at HEAD", so
    # reporting it alongside the push that invalidated it says the new head is
    # approved when nobody has read it.
    verdict_sha=""; verdict_state=""
  fi

  # Merge state is the author's business — they own the merge. A reviewer
  # watching the same PR has nothing to do about a conflict with base.
  #
  # Read AFTER the tick's activity, not before: a comment landing in the same
  # poll interval as a conflict would otherwise be answered with a bare `DIRTY`
  # that carries no re-arm line, and the caller re-spawns off a fresh clock —
  # filtering that comment out for good. `report_stop` folds anything in hand.
  # `watch-issue.sh` orders its closure branch the same way, for the same reason.
  if [ "$ROLE" = author ]; then
    MSTATUS=$(printf '%s' "$J" | jq -r '.merge.status')
    MCAUSE=$(printf '%s' "$J" | jq -r '.merge.cause // ""')
    # A base that moved on does NOT stop the watch. It clears with one "Update
    # branch" click and, under a merge queue, often without one — so ending the
    # wait on it loses the merge this stage exists to catch. It rides out on the
    # window's own IDLE instead, which is where the caller is already told to
    # look for why nothing merged.
    idle_merge=""
    [ "$MSTATUS" = behind ] && idle_merge=behind
    # Surfaced rather than acted on: the remedy is a person re-running
    # tests/fixtures/capture-enums.sh and deciding what the new value means, so
    # the watch keeps running and names it on the window it was going to report
    # anyway. Silent is the one thing it must not be.
    [ "$MSTATUS" = unrecognised ] && idle_merge="unrecognised:$MCAUSE"
    # A conflict is worth stopping for at any stage — it is never the normal
    # state of a PR, and nothing the reviewer does clears it.
    [ "$MSTATUS" = dirty ] && report_stop DIRTY
    # A terminal block is only a stop once the review is over. While a review is
    # running it is the NORMAL state of a healthy PR: with
    # `required_conversation_resolution` on, one open thread makes GitHub report
    # BLOCKED, and with no required approver `reviewDecision` is empty, so the
    # cause falls through to terminal. Stopping there ends the review watch on
    # its first tick, every round, for the ordinary reason that a reviewer has
    # opened a thread. `--merge-stage` is what says the review is done.
    if [ "$MERGE_STAGE" = 1 ] && [ "$MSTATUS" = blocked ] && [ "$MCAUSE" = terminal ]; then
      report_stop BLOCKED "cause=terminal"
    fi
    [ "$MERGE_STAGE" = 0 ] && [ "$MSTATUS" = blocked ] && [ "$MCAUSE" = terminal ] \
      && idle_merge=blocked
  fi

  [ "$saw_ready" = 1 ] && report_burst

  if [ "$changed" = 1 ]; then
    poll_reset
    [ "$settle_until" = 0 ] && settle_cap=$(( $(date +%s) + SETTLE_MAX ))
    settle_until=$(( $(date +%s) + SETTLE ))
  fi

  if [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
     && { [ "$(date +%s)" -ge "$settle_until" ] || [ "$(date +%s)" -ge "$settle_cap" ]; }; then
    if have_burst; then
      report_burst
    else
      # Everything the settle was holding has been withdrawn. Drop back to
      # watching rather than reporting a burst with nothing in it.
      settle_until=0; settle_cap=0
    fi
  fi

  { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out && report_idle
  poll_nap
done
