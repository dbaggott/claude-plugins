#!/usr/bin/env bash
# List a PR's unresolved review threads, or resolve one. Both sides of a review
# need this: the author enumerates what is still outstanding before claiming a
# round is handled, and `reviewer` resolves its own threads once the finding is
# answered.
#
#   pr-threads.sh <owner/repo> <pr> [--mine]
#   pr-threads.sh <owner/repo> <pr> --resolve <thread-id>
#
# Listing prints one compact JSON object per line — id, path, line, author, body
# — then a result line, then exits 0:
#   {"id":"PRRT_…","path":"api/server.go","line":42,"author":"…","body":"…"}
#   result=OK count=<n>
#
#   result=OK resolved=<thread-id>          # --resolve
#   result=ERROR reason=bad-args|no-slug|graphql|graphql-shape|resolve
#
# JSONL rather than one array so the common reads need no jq at all: an agent
# reads the objects directly, and a caller that only wants the count (the
# `BLOCKED`-cause diagnostic in `git-workflow`) reads `count=` off the result
# line instead of piping through `wc -l`. `jq -s .` reassembles an array if one
# is ever wanted.
#
# `--mine` filters to threads whose FIRST comment is authored by the configured
# reviewer bot — what `reviewer` needs to find its own outstanding findings, and
# what an author must NOT use, since a human reviewer's threads block the merge
# just as surely.
#
# Match the bot on the App `slug`, not `bot_login`. GraphQL reports a Bot
# author's `login` WITHOUT the `[bot]` suffix (e.g. `agent-reviewer-<you>`), so
# matching `…[bot]` never hits and `--mine` silently returns nothing — a filter
# that finds no outstanding findings looks exactly like having none. Both
# spellings are accepted here so the same flag works if GitHub ever reports the
# suffixed form through GraphQL too.
#
# ⚠️ AN EMPTY SLUG IS FATAL UNDER `--mine`, NOT A DEFAULT. An empty match string
# selects no thread at all, which reads as "nothing outstanding" — the same
# silent-blindness shape the watcher's slug guard exists to prevent. Bail instead.
#
# Runs under whatever auth the caller provides, and `GH_TOKEN` is deliberately
# NOT unset here. The reviewer resolves its own threads under its own App
# credentials, which needs `contents: write` — an App token without it gets
# `FORBIDDEN: Resource not accessible by integration` from
# `resolveReviewThread`. `reviewer-setup` grants it.
#
# An author reading threads has no `GH_TOKEN` set and falls through to their own
# `gh` auth, which is the same behaviour they had before.
#
# Reads the first 100 threads. A PR past that is far outside anything this
# workflow produces, and the failure would be under-reporting rather than a wrong
# answer — but it is a cap, so it is stated rather than left to be discovered.
set -euo pipefail

REPO="${1:-}"; PR="${2:-}"; shift 2 2>/dev/null || true

# Every branch either shifts or breaks. A branch reaching a `shift 2` on a
# one-element argv fails it, leaving `$1` unchanged and spinning the loop forever
# — a hang, which is the one failure mode a caller reading `result=` lines cannot
# diagnose at all.
MINE=0; RESOLVE=""; bad=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mine)    MINE=1; shift ;;
    --resolve) RESOLVE="${2:-}"; [ -n "$RESOLVE" ] || { bad=1; break; }; shift 2 ;;
    *)         bad=1; break ;;
  esac
done

# `--mine` and `--resolve` are refused together rather than silently ignoring
# one: they are different operations, and which one a caller meant is not
# recoverable from the pair.
[ "$MINE" = 1 ] && [ -n "$RESOLVE" ] && bad=1
if [ -z "$REPO" ] || [ -z "$PR" ] || [ "${REPO%/*}" = "$REPO" ]; then bad=1; fi

if [ "$bad" = 1 ]; then
  echo "result=ERROR reason=bad-args"
  exit 0
fi
OWNER="${REPO%%/*}"; NAME="${REPO#*/}"

if [ -n "$RESOLVE" ]; then
  # shellcheck disable=SC2016  # `$id` is a GraphQL variable bound by -f, not a
  # shell one — expanding it here would send the value in place of the binding.
  if gh api graphql -f query='mutation($id:ID!) {
        resolveReviewThread(input:{threadId:$id}) { thread { isResolved } }
      }' -f id="$RESOLVE" >/dev/null 2>&1; then
    echo "result=OK resolved=$RESOLVE"
  else
    echo "result=ERROR reason=resolve"
  fi
  exit 0
fi

ME=""
if [ "$MINE" = 1 ]; then
  CONFIG="${DNBG_REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/reviewer}/config.json"
  ME=$(jq -r '.slug // empty' "$CONFIG" 2>/dev/null || true)
  if [ -z "$ME" ] || [ "$ME" = null ]; then
    echo "result=ERROR reason=no-slug"
    exit 0
  fi
fi

# shellcheck disable=SC2016  # GraphQL variables again, bound by the -F flags below.
if ! RAW=$(gh api graphql \
      -f query='query($owner:String!,$repo:String!,$pr:Int!) {
        repository(owner:$owner, name:$repo) {
          pullRequest(number:$pr) {
            reviewThreads(first:100) {
              nodes { id isResolved path line comments(first:1){ nodes { author { login } body } } }
            }
          }
        }
      }' -f owner="$OWNER" -f repo="$NAME" -F pr="$PR" 2>/dev/null); then
  echo "result=ERROR reason=graphql"
  exit 0
fi

# `--arg me ""` with `$mine` false is a no-op filter, so one program serves both
# modes. Split from the fetch above so a parse failure is never reported as "no
# unresolved threads".
if ! OUT=$(echo "$RAW" | jq -c --arg me "$ME" --argjson mine "$MINE" '
      def author: .comments.nodes[0].author.login // "";
      .data.repository.pullRequest.reviewThreads.nodes
      | map(select(.isResolved == false))
      | map(select($mine == 0 or author == $me or author == ($me + "[bot]")))
      | .[]
      | {id, path, line, author: author, body: (.comments.nodes[0].body // "")}' 2>/dev/null); then
  echo "result=ERROR reason=graphql-shape"
  exit 0
fi

[ -n "$OUT" ] && printf '%s\n' "$OUT"
echo "result=OK count=$(printf '%s' "$OUT" | grep -c . || true)"
