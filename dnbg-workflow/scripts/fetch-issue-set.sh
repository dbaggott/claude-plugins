#!/usr/bin/env bash
# A tracking issue and every one of its sub-issues, as one forge-neutral object.
#
#   fetch-issue-set.sh <owner/repo> <parent>
#
# Prints the object, then exactly one result line, then exits 0:
#   {"parent":{"url":…,"number":…,"title":…,"body":…,"state":…,"created":…,
#              "body_edited":…},
#    "children":[{…the same fields…,"blocked_by":["<issue url>",…]}]}
#   result=OK now=<iso> children=<count>
#   result=ERROR reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape|set-overflow now=<iso>
#
# `body_edited` is null for a body never edited since filing. `blocked_by` holds
# URLs rather than numbers because a sub-issue may live in another repo of the
# same owner, where a bare number names a different issue. A parent with no
# sub-issues is `children: []`, not an error.
#
# `set-overflow` means a page came back short of its total — more sub-issues, or
# more blockers on one child, than one query asks for — so the snapshot would
# silently omit part of the set.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

[ "$#" -eq 2 ] || fail bad-args
REPO="$1"; N="$2"
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|*[!0-9]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# GitHub caps a parent at 100 sub-issues, so one page holds any set.
# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='fragment Fields on Issue { url number title body state createdAt lastEditedAt }
query($owner:String!, $repo:String!, $n:Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      ...Fields
      subIssues(first: 100) {
        totalCount
        nodes {
          ...Fields
          blockedBy(first: 50) { totalCount nodes { url } }
        }
      }
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

printf '%s' "$ISSUE" | jq -e '
  (.subIssues.nodes | length) == .subIssues.totalCount
  and all(.subIssues.nodes[]; (.blockedBy.nodes | length) == .blockedBy.totalCount)' \
  >/dev/null 2>&1 || {
    # A false answer is the overflow; anything else is a payload that stopped
    # parsing, which must not be reported as a set too large to read.
    printf '%s' "$ISSUE" | jq -e '.subIssues.nodes | type == "array"' >/dev/null 2>&1 \
      && fail set-overflow
    fail issue-query-shape
  }

OUT=$(printf '%s' "$ISSUE" | jq -c '
  def fields: {url, number, title, body, state, created: .createdAt,
               body_edited: (.lastEditedAt // null)};
  { parent: fields,
    children: [ .subIssues.nodes[] | fields + {blocked_by: [.blockedBy.nodes[].url]} ] }' \
  2>/dev/null) || fail issue-query-shape

echo "$OUT"
echo "result=OK now=$(now_iso) children=$(printf '%s' "$OUT" | jq '.children | length')"
