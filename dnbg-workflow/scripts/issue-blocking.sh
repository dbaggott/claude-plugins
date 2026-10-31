#!/usr/bin/env bash
# The open issues one issue blocks: the sideways read of the blocked-by
# relation, where fetch-issue-set.sh walks down from a parent.
#
#   issue-blocking.sh <owner/repo> <n>
#
# Prints the URL of each open issue that issue <n> blocks, one per line, then
# exactly one result line, then exits 0:
#   result=OK count=<n>
#   result=ERROR reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape|set-overflow
#
# A closed blocked issue is in neither the list nor `count`. `count=0` is a
# complete, empty answer. `not-found` is a number resolving to no issue;
# `issue-query` a read that returned nothing usable; `issue-query-shape` a
# payload that did not parse, or a null node such as an issue the token cannot
# see; `set-overflow` a page shorter than its `totalCount`, which is reported
# rather than paged, so the caller never takes a truncated list for a complete
# one. Any ERROR prints no URLs.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail

fail() { echo "result=ERROR reason=$1"; exit 0; }

[ "$#" -eq 2 ] || fail bad-args
REPO="$1"; N="$2"
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|*[!0-9]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='query($owner:String!, $repo:String!, $n:Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      blocking(first: 50) { totalCount nodes { url state } }
    }
  }
}'

# `-F` for the number, which must reach GraphQL as an Int; `-f` for the owner and
# repo, so an all-digit name stays a String.
RAW=$(gh api graphql -f query="$Q" -f owner="$OWNER" -f repo="$NAME" -F n="$N" 2>/dev/null) || true
# Stdout is parsed regardless of exit status: an unresolvable issue or repo
# answers a null node plus a NOT_FOUND error, and `gh` exits 1 on it.
[ -n "$RAW" ] || fail issue-query
ISSUE=$(printf '%s' "$RAW" | jq -c '.data.repository.issue // empty' 2>/dev/null) \
  || fail issue-query-shape
if [ -z "$ISSUE" ]; then
  printf '%s' "$RAW" | jq -e 'any(.errors[]?; .type == "NOT_FOUND")' >/dev/null 2>&1 \
    && fail not-found
  fail issue-query
fi

# Shape first, so a payload that stopped parsing is never reported as a list too
# long to read.
printf '%s' "$ISSUE" | jq -e '
  .blocking | (.totalCount | type) == "number" and (.nodes | type) == "array"
              and all(.nodes[]; type == "object" and (.url | type) == "string"
                                and (.state | type) == "string")' \
  >/dev/null 2>&1 || fail issue-query-shape
printf '%s' "$ISSUE" | jq -e '.blocking | (.nodes | length) == .totalCount' >/dev/null 2>&1 \
  || fail set-overflow

printf '%s' "$ISSUE" | jq -r '.blocking.nodes[] | select(.state == "OPEN") | .url'
printf '%s' "$ISSUE" | jq -r '"result=OK count=\([.blocking.nodes[] | select(.state == "OPEN")] | length)"'
