#!/usr/bin/env bash
# What changed in an issue's body between two moments, as a unified diff.
#
#   issue-diff.sh <owner/repo> <n> --since=<iso> [--until=<iso>]
#
# Each moment resolves to the latest body snapshot at or before it; `--until`
# defaults to now, which is the current body. Prints the diff, its two header
# lines naming each snapshot's `editedAt` and editor, then exactly one result
# line, then exits 0:
#   --- base <iso> <login>
#   +++ head <iso> <login>
#   @@ … @@
#   result=OK base=<iso>|none head=<iso> editors=<login,…>
#   result=OK same=true
#   result=ERROR reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape|history-overflow|snapshot-deleted|diff-failed now=<iso>
#
# `base=none` means no snapshot exists at or before `--since` — normally because it
# predates the issue — so the head body prints as all additions, never as an empty
# diff a caller could read as "unchanged".
# `same=true` means both moments resolve to one snapshot and nothing else prints.
# `editors` is every login that wrote a snapshot after the base up to the head,
# in order, so an intermediate editor is visible even when the head's own editor
# is someone else.
#
# Snapshots come from GraphQL `userContentEdits`, whose `diff` field holds the
# whole body after each edit, not a diff. The creation body is its oldest entry,
# stamped at the issue's `createdAt`, and is attributed here to the issue author.
# A never-edited issue has no entries; its one snapshot is the current body.
# A revision someone deleted from the history has no body, and a moment that
# resolves to one is `snapshot-deleted` rather than silently a different base.
#
# Line endings are normalised to LF before diffing: a body saved through the web
# editor arrives with CRLF, and the diff is read for content.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

REPO="${1:-}"; N="${2:-}"
[ "$#" -ge 2 ] || fail bad-args
shift 2
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|*[!0-9]*) fail bad-args ;; esac

SINCE=""; UNTIL=""
for a in "$@"; do
  case "$a" in
    --since=*) [ -z "$SINCE" ] || fail bad-args; SINCE="${a#--since=}" ;;
    --until=*) [ -z "$UNTIL" ] || fail bad-args; UNTIL="${a#--until=}" ;;
    *) fail bad-args ;;
  esac
done
# Snapshot times are compared as strings, which orders correctly only because
# every value is this one fixed-width UTC form.
[[ "$SINCE" =~ $ISO_RE ]] || fail bad-args
[ -z "$UNTIL" ] || [[ "$UNTIL" =~ $ISO_RE ]] || fail bad-args
[ -z "$UNTIL" ] || [[ ! "$UNTIL" < "$SINCE" ]] || fail bad-args

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='query($owner:String!, $repo:String!, $n:Int!, $cursor:String) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      createdAt body author { login }
      userContentEdits(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { editedAt deletedAt editor { login } diff }
      }
    }
  }
}'

# A page cap, so a cursor that never reports its last page cannot loop forever.
MAX_PAGES=${MAX_PAGES:-50}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
: > "$TMP/nodes"
CURSOR=""; ISSUE=""
for (( page = 0; ; page++ )); do
  [ "$page" -lt "$MAX_PAGES" ] || fail history-overflow
  # `-F` for the number, which must reach GraphQL as an Int; `-f` for everything a
  # caller supplies as text, so an all-digit owner or repo stays a String.
  PAGE_ARGS=(); [ -z "$CURSOR" ] || PAGE_ARGS=(-f cursor="$CURSOR")
  RAW=$(gh api graphql -f query="$Q" -f owner="$OWNER" -f repo="$NAME" -F n="$N" \
          "${PAGE_ARGS[@]}" 2>/dev/null) || true
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
  printf '%s' "$ISSUE" | jq -c '.userContentEdits.nodes[]' >> "$TMP/nodes" 2>/dev/null \
    || fail issue-query-shape
  [ "$(printf '%s' "$ISSUE" | jq -r '.userContentEdits.pageInfo.hasNextPage')" = true ] || break
  CURSOR=$(printf '%s' "$ISSUE" | jq -r '.userContentEdits.pageInfo.endCursor')
done

# Oldest first. The API lists newest first, so reversing before the stable sort
# keeps two edits stamped in the same second in the order they were made. The
# newest snapshot is the current body, taken from the issue itself so a deleted
# newest revision still has one. The issue goes in by file, since even its one
# body can pass the per-argument cap on Linux.
printf '%s' "$ISSUE" | jq -c 'del(.userContentEdits)' > "$TMP/issue" \
  || fail issue-query-shape
SNAPS=$(jq -cs --slurpfile issues "$TMP/issue" '
  $issues[0] as $issue
  | ($issue.author.login // "ghost") as $author
  | if length == 0 then
      [{at: $issue.createdAt, editor: $author, body: $issue.body}]
    else
      reverse | sort_by(.editedAt) | map({
        at: .editedAt,
        editor: (if .editedAt == $issue.createdAt then $author
                 else (.editor.login // "ghost") end),
        body: (if .deletedAt then null else .diff end)})
      | .[-1].body = $issue.body
    end' "$TMP/nodes") || fail issue-query-shape

# Index of the latest snapshot at or before a moment, or -1 when the moment
# predates the issue.
at_or_before() {
  jq -r --arg t "$1" '[to_entries[] | select(.value.at <= $t) | .key] | last // -1' <<<"$SNAPS"
}
BASE=$(at_or_before "$SINCE")
if [ -n "$UNTIL" ]; then HEAD=$(at_or_before "$UNTIL")
else HEAD=$(( $(jq length <<<"$SNAPS") - 1 )); fi

if [ "$BASE" = "$HEAD" ]; then echo "result=OK same=true"; exit 0; fi

# The body of snapshot <i> into <file>, LF line endings.
body_to() {
  jq -e --argjson i "$1" '.[$i].body != null' <<<"$SNAPS" >/dev/null || fail snapshot-deleted
  jq -j --argjson i "$1" '.[$i].body' <<<"$SNAPS" | tr -d '\r' > "$2"
}
label() { jq -r --argjson i "$1" '"\(.[$i].at) \(.[$i].editor)"' <<<"$SNAPS"; }

if [ "$BASE" -lt 0 ]; then
  : > "$TMP/base"; BASE_LABEL="none"; BASE_AT="none"
else
  body_to "$BASE" "$TMP/base"; BASE_LABEL=$(label "$BASE")
  BASE_AT=$(jq -r --argjson i "$BASE" '.[$i].at' <<<"$SNAPS")
fi
body_to "$HEAD" "$TMP/head"
HEAD_AT=$(jq -r --argjson i "$HEAD" '.[$i].at' <<<"$SNAPS")
EDITORS=$(jq -r --argjson b "$BASE" --argjson h "$HEAD" '
  [.[($b + 1):($h + 1)][].editor] | reduce .[] as $e ([]; if index([$e]) then . else . + [$e] end)
  | join(",")' <<<"$SNAPS")

# `diff` exits 1 when the files differ, which is the expected case here.
RC=0
diff -u -L "base $BASE_LABEL" -L "head $(label "$HEAD")" "$TMP/base" "$TMP/head" || RC=$?
[ "$RC" -le 1 ] || fail diff-failed
echo "result=OK base=$BASE_AT head=$HEAD_AT editors=$EDITORS"
