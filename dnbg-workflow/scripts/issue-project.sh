#!/usr/bin/env bash
# Where an issue sits in a project: the tracking issue above it, and whether it
# is one itself. The reverse of fetch-issue-set.sh, which walks down from a
# parent.
#
#   issue-project.sh <owner/repo> <n>
#
# Exactly one result line, then exit 0:
#   result=OK parent=<url|none> tracking=<yes|no> children=<count>
#   result=ERROR reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape now=<iso>
#
# `parent` is the open issue this one is a sub-issue of, which may live in
# another repo of the same owner. A closed parent is `none`: its project is over,
# so there is nothing left to orchestrate. `tracking` is yes when the body opens
# with `This is a **tracking issue**` (issue-workflow's tracking-issue.md) or
# the issue has sub-issues; `children` counts its sub-issues, open or closed.
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

# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='query($owner:String!, $repo:String!, $n:Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      body
      parent { url state }
      subIssues { totalCount }
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

LINE=$(printf '%s' "$ISSUE" | jq -r '
  (.subIssues.totalCount | if type == "number" then . else error end) as $c
  | (if .parent == null or .parent.state != "OPEN" then "none" else .parent.url end) as $p
  | ((.body // "") | test("^\\s*This is a \\*\\*tracking issue\\*\\*")) as $m
  | "parent=\($p) tracking=\(if $m or $c > 0 then "yes" else "no" end) children=\($c)"' \
  2>/dev/null) || fail issue-query-shape

echo "result=OK $LINE"
