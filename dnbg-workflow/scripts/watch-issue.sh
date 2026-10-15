#!/usr/bin/env bash
# Block until something happens on one or more issues, print what it was, and
# exit. The issue-side sibling of watch-pr.sh, sharing its curve, its clock and
# its re-arm contract.
#
#   watch-issue.sh <owner/repo> <n> [n...] --role=author|reviewer|orchestrator \
#     [--since=<iso>] [--slug=<login>] [--exclude=<pr-url,…>] \
#     [--wake-on=<kind,…>] [--exclude-login=<login,…>]
#
# Exactly one result line, then exit 0:
#   result=ACTIVITY issues=<n,…> kinds=<comment|linked-pr|body-edit,…> \
#     edited=<n:iso|n:none,…> [comments=<login:url,…>] [overflowed=<n,…>] \
#     [closed=<n,…>] [missing=<n,…>] <re-arm fields> now=<iso>
#   result=CLOSED   issues=<n,…> [missing=<n,…>] [<re-arm fields>] now=<iso>
#   result=IDLE     [missing=<n,…>] <re-arm fields> now=<iso>
#   result=ERROR    reason=<source> now=<iso>
#
# THE RE-ARM CONTRACT. Results a caller re-arms from carry a `── re-arm ──` line,
# the next invocation with every argument filled in: `since` set to this run's
# `now`, and any newly-seen PR folded into `--exclude`. An agent runs that line;
# a script reads the same values from the result line instead of parsing the
# command: `now=` is the next `--since`, and the re-arm fields are
# `wake-on=<kind,…>`, then `exclude=<pr-url,…>` and `exclude-login=<login,…>`
# when non-empty. A result with no re-arm line carries no re-arm fields.
#
# THE FIRST-ARM RULE, the contract's first clause: a first arm has no printed
# line, so its `--since` is the time of your own last action that the awaited
# event responds to — posting the response, pushing the commit, dispatching the
# agent — noted BEFORE that action, never the clock at arm time. Activity at or
# before `since` is filtered out for good, so a clock stamped at arm time loses
# whatever another party did between your action and the arm, and the watch
# then waits for an event that has already happened. If that party may already
# have acted, read the issue once before arming: a wait is for what has not
# happened yet.
#
# `--wake-on` picks the event kinds that wake the watch, from `comment`,
# `linked-pr`, `body-edit` and `close`; without `close`, a closed issue stays in
# the set and reports nothing. `--exclude-login` adds logins whose comments are
# ignored, in both spellings as below, to the role's own. Each role is a preset
# over the two, which the flags override:
#
#   author, reviewer  every kind; ignores `--slug`
#   orchestrator      every kind but `body-edit`; ignores no login
#
# A harness waiting for a body edit made under the operator's own login, which
# no role's comment filter can single out, wakes on that alone:
#   --role=author --wake-on=body-edit,close
#
# `missing=` names numbers that resolve to no issue — a typo, a transfer, a PR
# number. They leave the watch set rather than being re-asked every tick, so the
# field is how a caller learns one of its issues is no longer being watched.
#
# `closed=` appears when an issue closes while activity on the OTHERS is still
# settling. Both facts ride one line because reporting only the closure would
# drop that activity for good — the re-arm sets `since` past it.
#
# `edited=` carries each watched issue's body-edit stamp, so a caller comparing a
# comment against whether the body actually moved needs no second call. A body
# never edited reads `none` — a reading, not a missing field: "the body has not
# moved" is exactly the answer that check wants, and an empty value would be
# taken for a failed fetch.
#
# WHAT IT WATCHES, AND WHY BOTH IN ONE SCRIPT. A comment, a body edit, a linked
# PR appearing, and the issue closing are four questions about one thing, and one
# batched query answers all four for any number of issues. Splitting them would
# buy separate result vocabularies and cost a request per question per tick.
#
# The orchestrator role takes no `--slug` and by default excludes no login: the author it
# dispatched, the operator and the orchestrator itself all post under one account,
# so it tells comments apart by their first line instead. It never wakes on what
# only the orchestrator's own bookkeeping produces: a body edit, a comment opening
# `Decision log:`, a `Claimed by` comment carrying this session's id
# (`${CLAUDE_CODE_SESSION_ID:0:8}`), or the reviewer's `Claude Code is acting as
# reviewer` note. A `Claimed by` with any other id is a sibling claiming the issue,
# and wakes it. `comments=` lists every other comment inside the window, oldest
# first, as its author's login and its URL. `overflowed=` names issues whose page
# of comments may not reach back to `since`, so `comments=` can be missing some;
# the caller reads those threads in full.
#
# ⚠️ THE EXCLUSION IS AN EXACT LOGIN MATCH — of both spellings, `<slug>` and
# `<slug>[bot]`, since a GitHub App posts under the suffixed one — AND THE TWO
# ROLES EXCLUDE DIFFERENT ONES. A reviewer excludes its bot; an author excludes their own account — and
# the operator's login is a SUBSTRING of the bot's, so a substring match on the
# author side drops every reviewer comment the watch exists to catch. That
# failure is silent: the watch reports a quiet issue while seeing everything.
set -euo pipefail
unset GH_TOKEN

_poll_argv="$*"

REPO=""; ROLE=""; SINCE=""; SLUG=""; EXCLUDE=""; NUMS=""; WAKE_ON=""; XLOGINS=""
bad=0
for arg in "$@"; do
  case "$arg" in
    --role=*)    ROLE="${arg#--role=}" ;;
    --since=*)   SINCE="${arg#--since=}" ;;
    --slug=*)    SLUG="${arg#--slug=}" ;;
    --exclude=*) EXCLUDE="${arg#--exclude=}" ;;
    --wake-on=*) WAKE_ON="${arg#--wake-on=}"; [ -n "$WAKE_ON" ] || bad=1 ;;
    --exclude-login=*) XLOGINS="$XLOGINS,${arg#--exclude-login=}" ;;
    --*)         bad=1 ;;
    *) if [ -z "$REPO" ]; then REPO="$arg"
       else case "$arg" in ''|*[!0-9]*) bad=1 ;; *) NUMS="$NUMS $arg" ;; esac
       fi ;;
  esac
done

# Before lib-poll.sh, which applies its own `WINDOW` default the moment it is
# sourced — set after, this never fires and both roles silently get the long one.
WINDOW=${WINDOW:-$([ "$ROLE" = author ] && echo 1800 || echo 21600)}

# shellcheck source=./lib-poll.sh
. "$(dirname "$0")/lib-poll.sh"
# shellcheck source=./lib-watch.sh
. "$(dirname "$0")/lib-watch.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
fatal() { echo "result=ERROR reason=$1 now=$(poll_now_iso)"; exit 0; }

case "$ROLE" in author|reviewer|orchestrator) ;; *) bad=1 ;; esac
[ -n "$REPO" ] || bad=1
case "$REPO" in */*) ;; *) bad=1 ;; esac
[ -n "$NUMS" ] || bad=1
[ -n "$SINCE" ] || SINCE="1970-01-01T00:00:00Z"

if [ -z "$SLUG" ] && [ "$ROLE" = author ]; then
  SLUG=$(gh api user --jq .login 2>/dev/null) || SLUG=""
fi
if [ "$ROLE" = orchestrator ]; then
  [ -z "$SLUG" ] || bad=1
else
  [ -n "$SLUG" ] || bad=1
fi

# Normalised to one sorted, comma-separated list each, so the re-arm line and the
# result field carry the same value however the caller spelled it.
csv() { tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u | paste -sd, - || true; }
if [ -z "$WAKE_ON" ]; then
  case "$ROLE" in orchestrator) WAKE_ON=comment,linked-pr,close ;; *) WAKE_ON=comment,linked-pr,body-edit,close ;; esac
fi
WAKE_ON=$(printf '%s' "$WAKE_ON" | csv)
[ -n "$WAKE_ON" ] || bad=1
for k in $(printf '%s' "$WAKE_ON" | tr ',' ' '); do
  case "$k" in comment|linked-pr|body-edit|close) ;; *) bad=1 ;; esac
done
XLOGINS=$(printf '%s' "$XLOGINS" | csv)
wakes() { case ",$WAKE_ON," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
[ "$bad" = 1 ] && fatal bad-args

# A review round on an issue is a stream — several comments and body edits over
# a couple of minutes — so a settle sized for one write would report it as a wake
# per write. SETTLE_MAX caps the hold, since that same stream is what can defer a
# wake indefinitely under a settle with none.
SETTLE=${SETTLE:-45}
SETTLE_MAX=${SETTLE_MAX:-300}

# Trimmed per entry: `grep -vxF` matches whole lines, so ` https://…` — the shape
# written after a comma — can never equal a URL the poll produces, and the entry
# is silently ignored. That is the hot loop the exclusion exists to prevent, with
# no diagnostic.
EXCLUDE_LINES=$(printf '%s' "$EXCLUDE" | tr ',' '\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true)

poll_init

SID="${CLAUDE_CODE_SESSION_ID:-}"; SID="${SID:0:8}"
# Every login whose comments are ignored, each in both spellings. Exact matches
# only — see the header.
XL=$(printf '%s\n%s\n' "$SLUG" "$XLOGINS" | tr ',' '\n' \
  | jq -Rsc 'split("\n") | map(select(. != "")) | map(., . + "[bot]")')
# Which comments count, as a jq function over one comment.
# shellcheck disable=SC2016  # jq variables, bound by each caller's --arg flags.
KEEP='def keep: (.author as $a | $xl | index($a) | not)
  and (if $role == "orchestrator" then
    (.head // "") as $h
    | ($h | startswith("Decision log:")
        or startswith("Claude Code is acting as reviewer")
        or (test("^claimed by"; "i") and $sid != "" and contains("(" + $sid + ")"))) | not
  else true end);'

hit_issues=""; hit_kinds=""; hit_overflow=""; closed_issues=""; new_prs=""; seen_missing=""
# What has already been accounted for. Without it the same comment satisfies the
# wake condition on every tick, so the settle window is extended forever and the
# watch never reports at all.
obs_sig=""; last_json=""
settle_until=0; settle_cap=0

# The `now` a report stamps once, so the re-arm line's `since` and the result
# line's `now=` are one value: a script re-arming from `now=` must get exactly
# what an agent running the line gets.
NOW=""
stamp_now() { NOW=$(poll_now_iso); }

rearm_exclude() {
  printf '%s\n%s\n' "$EXCLUDE_LINES" "$new_prs" \
    | grep -v '^[[:space:]]*$' | sort -u | paste -sd, - || true
}

rearm_cmd() {  # [issues-override]
  local ex nums="${1:-$NUMS}"
  ex=$(rearm_exclude)
  printf 'WINDOW=%s "%s/watch-issue.sh" %s%s --role=%s --since=%s%s%s --wake-on=%s%s' \
    "$WINDOW" "$HERE" "$REPO" "$nums" "$ROLE" "$NOW" \
    "${SLUG:+ --slug=$SLUG}" "${ex:+ --exclude=$ex}" "$WAKE_ON" "${XLOGINS:+ --exclude-login=$XLOGINS}"
}

# The re-arm line's flags as result-line fields, for a caller that is a script.
rearm_fields() {
  local ex
  ex=$(rearm_exclude)
  printf ' wake-on=%s%s%s' "$WAKE_ON" "${ex:+ exclude=$ex}" "${XLOGINS:+ exclude-login=$XLOGINS}"
}

# Reported on whatever result the watch reaches, so a number that resolves to
# nothing is named to the caller rather than silently dropped from the set.
missing_field() { [ -n "$seen_missing" ] && printf ' missing=%s' "$seen_missing" || true; }

report_idle() {
  stamp_now
  watch_rearm "$(rearm_cmd)"
  echo "result=IDLE$(missing_field)$(rearm_fields) now=$NOW"; exit 0
}

report_error() {
  [ "$settle_until" != 0 ] && report_hit
  echo "result=ERROR reason=$1 now=$(poll_now_iso)"
  exit 0
}

# `NONE` as the override means every watched issue is gone, so there is nothing
# to re-arm on and the line is omitted — the same reason CLOSED omits it.
report_hit() {  # [closed-list] [issues-override|NONE]
  local issues kinds edited comments="" overflowed="" fields=""
  stamp_now
  if [ "${2:-}" != NONE ]; then
    watch_rearm "$(rearm_cmd "${2:-}")"; fields=$(rearm_fields)
  fi
  issues=$(printf '%s\n' "$hit_issues" | tr ' ' '\n' | grep -v '^$' | sort -nu | paste -sd, - || true)
  kinds=$(printf '%s\n' "$hit_kinds" | tr ' ' '\n' | grep -v '^$' | sort -u | paste -sd, - || true)
  edited=$(printf '%s' "$last_json" | jq -r '
    [ .issues[] | "\(.number):\(.body_edited // "none")" ] | join(",")' 2>/dev/null || echo "")
  if [ "$ROLE" = orchestrator ]; then
    comments=$(printf '%s' "$last_json" | jq -r --arg s "$SINCE" --argjson xl "$XL" --arg role "$ROLE" --arg sid "$SID" "$KEEP"'
      [ .issues[].comments[] | select(.at > $s) | select(keep) ] | sort_by(.at)
      | map("\(.author):\(.url)") | join(",")' 2>/dev/null || echo "")
    overflowed=$(printf '%s\n' "$hit_overflow" | tr ' ' '\n' | grep -v '^$' | sort -nu | paste -sd, - || true)
  fi
  echo "result=ACTIVITY issues=$issues kinds=$kinds edited=$edited${comments:+ comments=$comments}${overflowed:+ overflowed=$overflowed}${1:+ closed=$1}$(missing_field)$fields now=$NOW"
  exit 0
}

while :; do
  # shellcheck disable=SC2086  # NUMS is a deliberately split list of numbers
  OUT=$("$HERE/fetch-issue-state.sh" "$REPO" $NUMS 2>/dev/null) || OUT=""
  LINE=$(printf '%s\n' "$OUT" | tail -1)
  J=$(printf '%s\n' "$OUT" | sed '$d')
  [ -n "$J" ] && last_json="$J"

  case "$LINE" in
    result=OK*)
      watch_ok issue-query
      # An unresolvable number is permanent, so it leaves the watch set on the
      # spot: kept in, it is re-asked every tick for the life of the watch and
      # the caller is never told which of its issues is not being watched.
      case "$LINE" in
        *missing=*)
          gone="${LINE#*missing=}"; gone="${gone%% *}"
          # Appended, not replaced: each number leaves the set permanently, so
          # a later one overwriting an earlier one means the caller is never told
          # about the first — the one thing the field exists to prevent.
          seen_missing=$(printf '%s\n%s\n' "$seen_missing" "$gone" | tr ',' '\n' \
            | grep -v '^$' | sort -nu | paste -sd, - || true)
          for m in $(printf '%s' "$gone" | tr ',' ' '); do
            NUMS=$(printf '%s' "$NUMS" | tr ' ' '\n' | grep -vx "$m" | tr '\n' ' ')
          done
          NUMS=" $(printf '%s' "$NUMS" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
          ;;
      esac ;;
    *reason=issue-query-shape*) watch_fail_shape issue-query report_error ;;
    *reason=bad-args*|*reason=unsupported-forge*) fatal "$(r="${LINE#*reason=}"; printf %s "${r%% *}")" ;;
    *) watch_fail issue-query report_error ;;
  esac

  if [ "${LINE#result=OK}" = "$LINE" ]; then
    poll_reset
    [ "$settle_until" != 0 ] && [ "$(date +%s)" -ge "$settle_cap" ] && report_hit
    [ "$settle_until" = 0 ] && poll_timed_out && report_idle
    poll_nap; continue
  fi

  # An exact login match, never a substring — see the header.
  comment_hits=""; edit_hits=""; overflow=""; all_prs=""
  wakes comment && comment_hits=$(printf '%s' "$J" | jq -r --arg s "$SINCE" --argjson xl "$XL" --arg role "$ROLE" --arg sid "$SID" "$KEEP"'
    [ .issues[] | select([ .comments[] | select(.at > $s) | select(keep) ] | length > 0)
      | .number ] | join(" ")')
  wakes body-edit && edit_hits=$(printf '%s' "$J" | jq -r --arg s "$SINCE" '
    [ .issues[] | select((.body_edited // "") > $s) | .number ] | join(" ")')

  # A page that overflowed may hide comments inside the window, so the count is
  # checked rather than the window trusted. Overflow alone is not enough to say
  # it does: the page holds the NEWEST comments, so one whose oldest entry
  # predates `since` covers the window whatever the lifetime total is. Waking on
  # the total instead fires on every tick for any issue that ever passed a page
  # — a permanent wake loop on exactly the long discussions this watch is for.
  wakes comment && overflow=$(printf '%s' "$J" | jq -r --arg s "$SINCE" '
    [ .issues[]
      | select(.comments_total > .comments_returned)
      | select((.comments | length) == 0 or (([ .comments[].at ] | min) > $s))
      | .number ] | join(" ")')
  [ -z "$overflow" ] || hit_overflow="$hit_overflow $overflow"

  wakes linked-pr && all_prs=$(printf '%s' "$J" | jq -r '[.issues[].linked_prs[]] | unique | join("\n")')
  if [ -n "$all_prs" ] && [ -n "$EXCLUDE_LINES" ]; then
    all_prs=$(printf '%s\n' "$all_prs" | grep -vxF "$EXCLUDE_LINES" || true)
  fi
  pr_hits=""
  if [ -n "$all_prs" ]; then
    new_prs="$all_prs"
    pr_hits=$(printf '%s' "$J" | jq -r --arg urls "$all_prs" '
      ($urls | split("\n")) as $new
      | [ .issues[] | select([ .linked_prs[] | select(. as $u | $new | index($u)) ] | length > 0)
          | .number ] | join(" ")')
  fi

  for pair in "comment:$comment_hits" "body-edit:$edit_hits" "linked-pr:$pr_hits" "comment:$overflow"; do
    kind="${pair%%:*}"; nums="${pair#*:}"
    if [ -n "$nums" ]; then
      hit_issues="$hit_issues $nums"; hit_kinds="$hit_kinds $kind"
    fi
  done

  closed_issues=""
  wakes close && closed_issues=$(printf '%s' "$J" | jq -r '[.issues[] | select(.state != "OPEN") | .number] | join(",")')
  if [ -n "$closed_issues" ]; then
    # AFTER the hits are computed, not before. A closure and a sibling's first
    # activity can land in one tick — up to a full poll interval apart in real
    # time — and answering the closure alone drops that activity: the re-arm sets
    # `since` past it, so it is filtered out for good rather than deferred.
    #
    # The closed ones leave the watch set either way. Re-arming with them still in
    # it reports the same closure on the next tick, forever, and the header tells
    # callers to re-arm from the line printed here.
    remaining=$(printf '%s' "$J" | jq -r '[.issues[] | select(.state == "OPEN") | .number] | join(" ")')

    # Anything in hand rides out as one line, with the closure as a field.
    if [ -n "$hit_issues" ] || [ "$settle_until" != 0 ]; then
      if [ -n "$remaining" ]; then report_hit "$closed_issues" " $remaining"
      else                         report_hit "$closed_issues" NONE; fi
    fi

    stamp_now
    fields=""
    if [ -n "$remaining" ]; then
      watch_rearm "$(rearm_cmd " $remaining")"; fields=$(rearm_fields)
    fi
    echo "result=CLOSED issues=$closed_issues$(missing_field)$fields now=$NOW"; exit 0
  fi

  # Counted rather than merely present, so a SECOND comment extends the window
  # and the first one does not extend it forever.
  sig=$(printf '%s' "$J" | jq -r --arg s "$SINCE" --argjson xl "$XL" --arg role "$ROLE" --arg sid "$SID" \
    --arg wake ",$WAKE_ON," "$KEEP"'
    def on($k): $wake | contains("," + $k + ",");
    [ (if on("comment") then [ .issues[].comments[] | select(.at > $s) | select(keep) ] | length else 0 end),
      (if on("body-edit") then [ .issues[] | select((.body_edited // "") > $s) ] | length else 0 end),
      (if on("linked-pr") then [ .issues[].linked_prs[] ] | length else 0 end) ] | join("/")')
  changed=0
  if [ -n "$hit_issues" ] && [ "$sig" != "$obs_sig" ]; then changed=1; obs_sig="$sig"; fi

  if [ "$changed" = 1 ]; then
    poll_reset
    [ "$settle_until" = 0 ] && settle_cap=$(( $(date +%s) + SETTLE_MAX ))
    settle_until=$(( $(date +%s) + SETTLE ))
  fi

  if [ "$settle_until" != 0 ] \
     && { [ "$(date +%s)" -ge "$settle_until" ] || [ "$(date +%s)" -ge "$settle_cap" ]; }; then
    report_hit
  fi

  [ "$settle_until" = 0 ] && poll_timed_out && report_idle
  poll_nap
done
