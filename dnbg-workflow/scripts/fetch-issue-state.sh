#!/usr/bin/env bash
# Everything one watch tick needs to know about a set of issues, as one
# forge-neutral object.
#
#   fetch-issue-state.sh <owner/repo> <n> [n...]
#
# Prints the object, then exactly one result line, then exits 0:
#   {"issues":[{"number":…,"state":…,"body_edited":…,"comments":[…],
#               "comments_total":…,"comments_returned":…,"linked_prs":[…]}],
#    "missing":[…]}
#   result=OK now=<iso> [missing=<n,n>]
#   result=ERROR reason=bad-args|issue-query|issue-query-shape now=<iso>
#
# One aliased query per tick for any N. The batch is the point: a watch over
# eight issues costs the same request as one, and state, the body-edit stamp,
# the conversation and the linked PRs all arrive together — none of which a
# comments-only source could answer.
#
# ⚠️ A BAD ISSUE NUMBER MUST NOT BLIND THE WATCH. GraphQL answers an
# unresolvable alias with null for that alias, valid data for every other, and
# an errors array — while `gh` exits 1. So stdout is parsed regardless of exit
# status, and a NOT_FOUND alias is reported once in `missing` and dropped rather
# than counted as a transient failure. Both natural implementations get this
# wrong: `if RAW=$(gh api …)` discards the issues that answered, and ignoring the
# status makes the bad alias read as "nothing new".
#
# A discovery source this query deliberately does NOT ask declares itself here, in
# the form tests/coupling.bats reads. Adding a fourth source to the skills'
# discovery block without either asking it or writing a line like this fails that
# test — the divergence has to be a decision someone made, not one that accumulated.
#
# PR-SOURCE-EXEMPT: gh search prs — it is the only discovery source with index
# lag, so the timeline connection above already sees everything it would, sooner.
# Discovery keeps it for the one thing a poll does not need: finding a sibling in
# a DIFFERENT repo, which a caller re-runs on wake anyway.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; nothing above this line is
# GitHub-shaped.
set -euo pipefail

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO="${1:-}"; shift || true
[ -n "$REPO" ] || fail bad-args
case "$REPO" in */*) ;; *) fail bad-args ;; esac
[ "$#" -gt 0 ] || fail bad-args
for n in "$@"; do case "$n" in ''|*[!0-9]*) fail bad-args ;; esac; done

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# `comments` takes no `since` argument — GraphQL answers argumentNotAccepted — so
# a page is taken and filtered by the caller. `totalCount` against the returned
# count is what tells a filtered window from an overflowed one.
COMMENT_PAGE=${COMMENT_PAGE:-20}

# Owner and name are bound as variables rather than interpolated: they reach
# here straight from a caller's argument, and one carrying a quote or a brace
# would build a malformed query for the life of the watch, reported as an
# `issue-query` error indistinguishable from an outage. The issue numbers are
# built into the string because an ALIAS cannot be a variable.
# shellcheck disable=SC2016  # GraphQL variables, bound by the -F flags below.
Q='query($owner:String!, $repo:String!) {
  repository(owner: $owner, name: $repo) {'
for n in "$@"; do
  Q="$Q
    i${n}: issue(number: ${n}) {
      number state lastEditedAt
      comments(last: ${COMMENT_PAGE}) {
        totalCount
        nodes { author { login } createdAt url }
      }
      closedByPullRequestsReferences(first: 20, includeClosedPrs: true) { nodes { url } }
      timelineItems(last: 50, itemTypes: [CROSS_REFERENCED_EVENT]) {
        nodes { ... on CrossReferencedEvent { source { ... on PullRequest { url } } } }
      }
    }"
done
Q="$Q
  }
}"

RAW=$(gh api graphql -f query="$Q" -F owner="$OWNER" -F repo="$NAME" 2>/dev/null) || true
[ -n "$RAW" ] || fail issue-query

OUT=$(printf '%s' "$RAW" | jq -c '
  (.data.repository // {}) as $r
  | [ $r | to_entries[] | select(.value != null) | .value | {
        number: .number,
        state:  .state,
        body_edited: (.lastEditedAt // null),
        comments_total:    (.comments.totalCount // 0),
        comments_returned: ((.comments.nodes // []) | length),
        comments: ((.comments.nodes // []) | map({
            author: (.author.login // ""), at: .createdAt, url: .url })),
        linked_prs: (
          (((.closedByPullRequestsReferences.nodes // []) | map(.url))
           + ((.timelineItems.nodes // []) | map(.source.url // empty)))
          | map(select(. != null and . != "")) | unique)
      } ]
  | { issues: ., missing: [] }' 2>/dev/null) || fail issue-query-shape

# An alias that resolved to null is a permanent condition for that issue — a
# transferred issue, a deleted one, a typo, or a PR number, since issue(number:)
# does not resolve a PR. Naming it once and dropping it is the only handling that
# neither blinds the watch nor counts toward a transient streak.
ASKED=$(printf '%s\n' "$@" | sort -u)
# `comm` compares lexicographically, so a numeric sort makes it report issues
# that answered as missing — 9 against 10 is the smallest case. `-u` because a
# number repeated in argv is not a missing issue either.
GOT=$(printf '%s' "$OUT" | jq -r '.issues[].number' | sort -u)
MISSING=$(comm -23 <(printf '%s\n' "$ASKED") <(printf '%s\n' "$GOT") | tr '\n' ',' | sed 's/,$//')

if [ -n "$MISSING" ]; then
  OUT=$(printf '%s' "$OUT" | jq -c --arg m "$MISSING" '.missing = ($m | split(",") | map(tonumber))')
fi

# Every alias unresolvable means the query answered nothing usable, which is the
# one case that is an error rather than a finding.
[ "$(printf '%s' "$OUT" | jq -r '.issues | length')" != 0 ] || fail issue-query

echo "$OUT"
echo "result=OK now=$(now_iso)${MISSING:+ missing=$MISSING}"
