#!/usr/bin/env bash
# Block until something happens on one or more issues, print what it was, and
# exit. The issue-side sibling of watch-pr.sh, sharing its curve, its clock and
# its re-arm contract.
#
#   watch-issue.sh <owner/repo> <n> [n...] --role=author|reviewer \
#     [--since=<iso>] [--slug=<login>] [--exclude=<pr-url,…>]
#
# Exactly one result line, then exit 0:
#   result=ACTIVITY issues=<n,…> kinds=<comment|linked-pr|body-edit,…> \
#     edited=<n:iso|n:none,…> [closed=<n,…>] [missing=<n,…>] now=<iso>
#   result=CLOSED   issues=<n,…> [missing=<n,…>] now=<iso>
#   result=IDLE     [missing=<n,…>] now=<iso>
#   result=ERROR    reason=<source> now=<iso>
#
# Results a caller re-arms from carry a `── re-arm ──` line, with `since` set to
# this run's own `now` and any newly-seen PR folded into `--exclude`.
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
# ⚠️ THE EXCLUSION IS AN EXACT LOGIN MATCH, AND THE TWO ROLES EXCLUDE DIFFERENT
# ONES. A reviewer excludes its bot; an author excludes their own account — and
# the operator's login is a SUBSTRING of the bot's, so a substring match on the
# author side drops every reviewer comment the watch exists to catch. That
# failure is silent: the watch reports a quiet issue while seeing everything.
set -euo pipefail
unset GH_TOKEN

_poll_argv="$*"

REPO=""; ROLE=""; SINCE=""; SLUG=""; EXCLUDE=""; NUMS=""
bad=0
for arg in "$@"; do
  case "$arg" in
    --role=*)    ROLE="${arg#--role=}" ;;
    --since=*)   SINCE="${arg#--since=}" ;;
    --slug=*)    SLUG="${arg#--slug=}" ;;
    --exclude=*) EXCLUDE="${arg#--exclude=}" ;;
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

case "$ROLE" in author|reviewer) ;; *) bad=1 ;; esac
[ -n "$REPO" ] || bad=1
case "$REPO" in */*) ;; *) bad=1 ;; esac
[ -n "$NUMS" ] || bad=1
[ -n "$SINCE" ] || SINCE="1970-01-01T00:00:00Z"

if [ -z "$SLUG" ] && [ "$ROLE" = author ]; then
  SLUG=$(gh api user --jq .login 2>/dev/null) || SLUG=""
fi
[ -n "$SLUG" ] || bad=1
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

hit_issues=""; hit_kinds=""; closed_issues=""; new_prs=""; seen_missing=""
# What has already been accounted for. Without it the same comment satisfies the
# wake condition on every tick, so the settle window is extended forever and the
# watch never reports at all.
obs_sig=""; last_json=""
settle_until=0; settle_cap=0

rearm_cmd() {  # [issues-override]
  local ex nums="${1:-$NUMS}"
  ex=$(printf '%s\n%s\n' "$EXCLUDE_LINES" "$new_prs" \
         | grep -v '^[[:space:]]*$' | sort -u | paste -sd, - || true)
  printf '"%s/watch-issue.sh" %s%s --role=%s --since=%s --slug=%s%s' \
    "$HERE" "$REPO" "$nums" "$ROLE" "$(poll_now_iso)" "$SLUG" \
    "${ex:+ --exclude=$ex}"
}

# Reported on whatever result the watch reaches, so a number that resolves to
# nothing is named to the caller rather than silently dropped from the set.
missing_field() { [ -n "$seen_missing" ] && printf ' missing=%s' "$seen_missing" || true; }

report_idle() {
  watch_rearm "$(rearm_cmd)"
  echo "result=IDLE$(missing_field) now=$(poll_now_iso)"; exit 0
}

report_error() {
  [ "$settle_until" != 0 ] && report_hit
  echo "result=ERROR reason=$1 now=$(poll_now_iso)"
  exit 0
}

# `NONE` as the override means every watched issue is gone, so there is nothing
# to re-arm on and the line is omitted — the same reason CLOSED omits it.
report_hit() {  # [closed-list] [issues-override|NONE]
  [ "${2:-}" = NONE ] || watch_rearm "$(rearm_cmd "${2:-}")"
  local issues kinds edited
  issues=$(printf '%s\n' "$hit_issues" | tr ' ' '\n' | grep -v '^$' | sort -nu | paste -sd, - || true)
  kinds=$(printf '%s\n' "$hit_kinds" | tr ' ' '\n' | grep -v '^$' | sort -u | paste -sd, - || true)
  edited=$(printf '%s' "$last_json" | jq -r '
    [ .issues[] | "\(.number):\(.body_edited // "none")" ] | join(",")' 2>/dev/null || echo "")
  echo "result=ACTIVITY issues=$issues kinds=$kinds edited=$edited${1:+ closed=$1}$(missing_field) now=$(poll_now_iso)"
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
  comment_hits=$(printf '%s' "$J" | jq -r --arg s "$SINCE" --arg slug "$SLUG" '
    [ .issues[] | select([ .comments[] | select(.at > $s) | select(.author != $slug) ] | length > 0)
      | .number ] | join(" ")')
  edit_hits=$(printf '%s' "$J" | jq -r --arg s "$SINCE" '
    [ .issues[] | select((.body_edited // "") > $s) | .number ] | join(" ")')

  # A page that overflowed may hide comments inside the window, so the count is
  # checked rather than the window trusted. Overflow alone is not enough to say
  # it does: the page holds the NEWEST comments, so one whose oldest entry
  # predates `since` covers the window whatever the lifetime total is. Waking on
  # the total instead fires on every tick for any issue that ever passed a page
  # — a permanent wake loop on exactly the long discussions this watch is for.
  overflow=$(printf '%s' "$J" | jq -r --arg s "$SINCE" '
    [ .issues[]
      | select(.comments_total > .comments_returned)
      | select((.comments | length) == 0 or (([ .comments[].at ] | min) > $s))
      | .number ] | join(" ")')

  all_prs=$(printf '%s' "$J" | jq -r '[.issues[].linked_prs[]] | unique | join("\n")')
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

  closed_issues=$(printf '%s' "$J" | jq -r '[.issues[] | select(.state != "OPEN") | .number] | join(",")')
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

    [ -n "$remaining" ] && watch_rearm "$(rearm_cmd " $remaining")"
    echo "result=CLOSED issues=$closed_issues$(missing_field) now=$(poll_now_iso)"; exit 0
  fi

  # Counted rather than merely present, so a SECOND comment extends the window
  # and the first one does not extend it forever.
  sig=$(printf '%s' "$J" | jq -r --arg s "$SINCE" --arg slug "$SLUG" '
    [ ([ .issues[].comments[] | select(.at > $s) | select(.author != $slug) ] | length),
      ([ .issues[] | select((.body_edited // "") > $s) ] | length),
      ([ .issues[].linked_prs[] ] | length) ] | join("/")')
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
