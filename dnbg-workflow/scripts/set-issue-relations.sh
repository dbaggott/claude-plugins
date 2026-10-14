#!/usr/bin/env bash
# Make one issue a sub-issue of a parent and record what blocks it.
#
#   set-issue-relations.sh <owner/repo> <child> --parent=<n> [--blocked-by=<n,...>]
#
# Every number is an issue in <owner/repo>. Prints exactly one result line, then
# exits 0:
#   result=OK parent=<n> blocked_by=<n,...>
#   result=ERROR reason=bad-args|unsupported-forge|issue-query|parent-conflict|parent-rejected|blocked-by-rejected now=<iso>
#
# `blocked_by` is the requested set, every member of which is in place on OK. Only
# the relationships missing at the time of the call are written, so a run that
# failed partway is safely run again: the forge rejects a relationship that
# already exists rather than ignoring it. Blockers the child already has and the
# call does not name are left alone.
#
# `parent-conflict` means the child already has a different parent. Setting a new
# one would silently move it out of the other project, so that is refused rather
# than done. On any rejection the forge's own message goes to stderr.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO="${1:-}"; CHILD="${2:-}"
[ "$#" -ge 2 ] || fail bad-args
shift 2
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
is_number "$CHILD" || fail bad-args

PARENT=""; BLOCKED_BY=""; SEEN_BLOCKED_BY=0
for a in "$@"; do
  case "$a" in
    --parent=*) [ -z "$PARENT" ] || fail bad-args; PARENT="${a#--parent=}" ;;
    --blocked-by=*)
      [ "$SEEN_BLOCKED_BY" = 0 ] || fail bad-args; SEEN_BLOCKED_BY=1
      BLOCKED_BY="${a#--blocked-by=}" ;;
    *) fail bad-args ;;
  esac
done
is_number "$PARENT" || fail bad-args
[ "$PARENT" != "$CHILD" ] || fail bad-args
BLOCKERS=()
if [ "$SEEN_BLOCKED_BY" = 1 ]; then
  IFS=, read -r -a BLOCKERS <<<"$BLOCKED_BY"
  [ "${#BLOCKERS[@]}" -gt 0 ] || fail bad-args
  for b in "${BLOCKERS[@]}"; do
    is_number "$b" && [ "$b" != "$CHILD" ] || fail bad-args
  done
  [ "$(printf '%s\n' "${BLOCKERS[@]}" | sort -u | wc -l)" -eq "${#BLOCKERS[@]}" ] || fail bad-args
fi

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

# Relationships are compared by URL, since a parent or blocker may live in
# another repository and its number alone would then match the wrong issue.
url_of() { echo "https://github.com/$REPO/issues/$1" | tr '[:upper:]' '[:lower:]'; }

CURRENT=$(gh issue view "$CHILD" --repo "$REPO" --json parent,blockedBy) || fail issue-query
HAS=$(jq -r '.parent.url // "" | ascii_downcase' <<<"$CURRENT" 2>/dev/null) || fail issue-query
if [ -z "$HAS" ]; then
  gh issue edit "$CHILD" --repo "$REPO" --parent "$PARENT" >/dev/null || fail parent-rejected
elif [ "$HAS" != "$(url_of "$PARENT")" ]; then
  echo "issue $CHILD already has parent $HAS" >&2
  fail parent-conflict
fi

MISSING=()
for b in ${BLOCKERS[@]+"${BLOCKERS[@]}"}; do
  jq -e --arg u "$(url_of "$b")" 'any(.blockedBy.nodes[]?; (.url | ascii_downcase) == $u)' \
       <<<"$CURRENT" >/dev/null || MISSING+=("$b")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  gh issue edit "$CHILD" --repo "$REPO" --add-blocked-by "$(IFS=,; echo "${MISSING[*]}")" >/dev/null \
    || fail blocked-by-rejected
fi

echo "result=OK parent=$PARENT blocked_by=$(IFS=,; echo "${BLOCKERS[*]-}")"
