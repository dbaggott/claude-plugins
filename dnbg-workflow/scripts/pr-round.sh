#!/usr/bin/env bash
# One review round's context in a single call: the delta diff, new activity, the
# standing verdict, and every unresolved thread. Both sides of a review need all
# four every round, and they were four separate steps of prose each — which a
# script cannot be two-thirds of, the way a prose sequence can.
#
#   pr-round.sh <owner/repo> <pr> <since-sha> <since-iso> <slug>
#
# <since-sha> is the SHA you last handled, empty on a first look; <since-iso>
# marks "handled up to here"; <slug> is the login whose own activity to exclude —
# your own, in both spellings GitHub uses for a bot (`<slug>`, `<slug>[bot]`).
# The same four values re-arm watch-pr.sh, so a caller carries one state tuple.
#
# Prints three delimited sections, then one result line, then exits 0:
#   ── diff ──
#   <unified diff>
#   ── activity ──
#   {"kind":"review|comment|inline","author":…,"at":…,"body":…}
#   ── threads ──
#   {"id":"PRRT_…","path":…,"line":…,"author":…,"body":…}
#   result=OK head=<sha> verdict=<state> verdict_sha=<sha> at_head=0|1
#     reviewed_after_head=0|1|unknown
#     review_decision=<state> verdict_src=<s> diff=delta|full|none|fail
#     activity=<n> reviews_src=<s> inline_src=<s> threads=<n> threads_src=<s>
#
#   result=ERROR reason=bad-args   # nothing was queried
#
# Each `<s>` is `ok`, `fail` (the request did not come back) or `shape` (it came
# back and stopped parsing) — pr-sources.sh's vocabulary, meaning the same there.
#
# ⚠️ A FAILED SOURCE STILL PRINTS `result=OK`, NAMING THAT SOURCE. The other three
# parts are a real answer, so suppressing them would be worse — but an empty
# section means "nothing there" only where its `_src` reads `ok`. A caller that
# ignores those fields reports a blind fetch as a quiet round.
#
# `verdict=` is passed through from pr-verdict.sh rather than recomputed. What
# counts as a verdict is pinned across exactly two files by tests/coupling.bats,
# and the extra `gh pr view` that costs is cheaper than a third copy of the set.
#
# Threads are not narrowed to the bot's. A human reviewer's thread blocks the
# merge just as surely; each line carries `author` for a caller that wants only
# its own. `pr-threads.sh --mine` is the narrowed read, for the resolve loop.
#
# Inline comments are read newest-first, one page: the endpoint is oldest-first
# by default, so on a PR past 100 inline comments page one is pure history and
# nothing new ever appears. The bound traded for is 100 new inline comments in
# one round.
#
# Runs under your own gh auth, like every read here — `GH_TOKEN` is unset, and
# the children inherit that.
set -euo pipefail
unset GH_TOKEN

REPO="${1:-}"; PR="${2:-}"; SINCE_SHA="${3-}"; SINCE="${4:-}"; SLUG="${5:-}"

# `<since-sha>` is the one argument that may be empty (a first look); the rest
# cannot do their job blank. An empty `<slug>` matches no login, so the caller's
# own posts come back as news — the failure watch-pr.sh refuses the same way.
if [ "$#" -ne 5 ] || [ -z "$REPO" ] || [ -z "$PR" ] || [ -z "$SINCE" ] || [ -z "$SLUG" ] \
   || [ "${REPO%/*}" = "$REPO" ]; then
  echo "result=ERROR reason=bad-args"
  exit 0
fi

DIR=$(dirname "$0")
# shellcheck source=./lib-activity.sh
. "$DIR/lib-activity.sh"

# Exact-key lookup over a `k=v` result line. A prefix match would read
# `verdict_sha=` as `verdict=`.
field() {  # <key> <line>
  awk -v k="$1" '{ for (i = 1; i <= NF; i++) { n = index($i, "=")
      if (n && substr($i, 1, n - 1) == k) { print substr($i, n + 1); exit } } }' <<<"$2"
}

# 1. The standing verdict, and the HEAD the diff is taken against.
# `reviewed_after_head` defaults to `unknown` rather than `0` for the same reason
# pr-verdict.sh never lets it collapse to `1`: a verdict source that failed knows
# nothing, and both callers gate the merge on this field reading `1`.
VRES=$("$DIR/pr-verdict.sh" "$REPO" "$PR")
HEAD=""; VERDICT=NONE; VSHA=""; AT_HEAD=0; REVIEWED_AFTER=unknown; DECISION=""
if [ "$(field result "$VRES")" = OK ]; then
  verdict_src=ok
  HEAD=$(field head "$VRES"); VERDICT=$(field verdict "$VRES")
  VSHA=$(field verdict_sha "$VRES"); AT_HEAD=$(field at_head "$VRES")
  REVIEWED_AFTER=$(field reviewed_after_head "$VRES")
  DECISION=$(field review_decision "$VRES")
else
  case "$(field reason "$VRES")" in
    *-shape) verdict_src=shape ;;
    *)       verdict_src=fail ;;
  esac
fi

# 2. The diff. `none` is the honest answer when the caller has already handled
# HEAD — an ACTIVITY round, where nobody pushed — and needs no request to reach.
DIFF=""
if [ -z "$SINCE_SHA" ]; then
  if DIFF=$(gh pr diff "$PR" --repo "$REPO" 2>/dev/null); then diff_src="full"
  else diff_src="fail"; DIFF=""; fi
elif [ -z "$HEAD" ]; then
  diff_src="fail"   # the verdict call carries HEAD, and it failed
elif [ "$SINCE_SHA" = "$HEAD" ]; then
  diff_src="none"
elif DIFF=$(gh api "repos/$REPO/compare/$SINCE_SHA...$HEAD" \
              -H "Accept: application/vnd.github.diff" 2>/dev/null); then
  diff_src="delta"
else
  diff_src="fail"; DIFF=""
fi

# 3. Activity since `$SINCE`, from two endpoints with two statuses: review bodies
# and conversation comments come from `gh pr view`, inline findings do not appear
# there at all. Fetch and parse are split at each so a payload that stops parsing
# is never reported as "nothing new".
REVS=""; reviews_src=ok
# Both halves come from one fetch, which is also the tick watch-pr.sh polls, so
# a caller reads the same objects whichever produced them and the filters below
# read one shape rather than two raw payloads.
STATE_OUT=$("$(dirname "$0")/fetch-pr-state.sh" "$REPO" "$PR" 2>/dev/null) || STATE_OUT=""
STATE_LINE=$(printf '%s\n' "$STATE_OUT" | tail -1)
STATE_JSON=$(printf '%s\n' "$STATE_OUT" | sed '$d')

INLINE=""; inline_src=ok
case "$STATE_LINE" in
  result=OK*)
    REVS=$(printf '%s' "$STATE_JSON" | jq -c --arg s "$SINCE" --arg slug "$SLUG" \
             "$ACTIVITY_JQ_REVIEWS" 2>/dev/null) || { reviews_src=shape; REVS=""; }
    INLINE=$(printf '%s' "$STATE_JSON" | jq -c '.inline' \
             | jq -c --arg s "$SINCE" --arg slug "$SLUG" "$ACTIVITY_JQ_INLINE" 2>/dev/null) \
             || { inline_src=shape; INLINE=""; }
    case "$STATE_LINE" in *degraded=inline-comments*) inline_src=fail ;; esac ;;
  *reason=*-shape*) reviews_src=shape; inline_src=shape ;;
  *)                reviews_src=fail;  inline_src=fail ;;
esac

# 4. Every unresolved thread, via the sibling that already owns the GraphQL. It
# prints JSONL and then its result line, so the last line is the status and the
# rest is the payload.
TRES=$("$DIR/pr-threads.sh" "$REPO" "$PR")
TLAST=$(printf '%s\n' "$TRES" | tail -1)
THREADS=$(printf '%s\n' "$TRES" | sed '$d')
TCOUNT=0
if [ "$(field result "$TLAST")" = OK ]; then
  threads_src=ok
  TCOUNT=$(field count "$TLAST")
else
  THREADS=""
  case "$(field reason "$TLAST")" in
    *-shape) threads_src=shape ;;
    *)       threads_src=fail ;;
  esac
fi

ACTIVITY=$(printf '%s\n%s\n' "$REVS" "$INLINE" | grep -v '^[[:space:]]*$' || true)

printf '── diff ──\n'
[ -n "$DIFF" ] && printf '%s\n' "$DIFF"
printf '── activity ──\n'
[ -n "$ACTIVITY" ] && printf '%s\n' "$ACTIVITY"
printf '── threads ──\n'
[ -n "$THREADS" ] && printf '%s\n' "$THREADS"

echo "result=OK head=$HEAD verdict=$VERDICT verdict_sha=$VSHA at_head=$AT_HEAD" \
     "reviewed_after_head=$REVIEWED_AFTER" \
     "review_decision=$DECISION verdict_src=$verdict_src diff=$diff_src" \
     "activity=$(printf '%s' "$ACTIVITY" | grep -c . || true)" \
     "reviews_src=$reviews_src inline_src=$inline_src" \
     "threads=$TCOUNT threads_src=$threads_src"
