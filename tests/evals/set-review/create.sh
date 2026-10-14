#!/usr/bin/env bash
#
# Set-review eval: does `issue-reviewer`, handed a tracking issue, find what a
# deliberately incomplete decomposition is missing?
#
#   tests/evals/set-review/create.sh [owner/repo]   # default dbaggott/dnbg-watch-testbed
#
# Files fixtures/ as a scratch tracking issue with its sub-issues and one
# blocked-by edge, then prints the parent's URL. Review that URL with
# `issue-reviewer`. The review passes when its round comments report each planted
# defect on the issue SKILL.md's attach rules name:
#
#   - Coverage gap, on the parent: R4 is in no child's `Covers` line and carries
#     no end-to-end or deferred marking.
#   - Unrealized dependency, on the checker child: its first acceptance criterion
#     runs against the output of the export child's script, and the checker has
#     neither a blocked-by edge nor a `Depends on` entry for it.
#
# The import child's edge to the export child is real and declared, so a review
# that flags it has misread the check.
#
# Nothing here grades: the round comments are the result, read by hand. Close the
# scratch issues once they have been read.
#
# Prints the parent URL, then one result line, and exits 0:
#   result=OK parent=<url> children=<url,url,url>
#   result=ERROR reason=bad-args|create-failed|link-failed [created=<url,…>]
#
# `created` names any issues already filed when a later step failed, so they can
# be closed rather than left open in the testbed.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FIX="$HERE/fixtures"
REPO="${1:-dbaggott/dnbg-watch-testbed}"

CREATED=""
fail() { echo "result=ERROR reason=$1${CREATED:+ created=$CREATED}"; exit 0; }
# <url> -> records it as filed, for `fail`
filed() { [ -n "$1" ] || return 1; CREATED="${CREATED:+$CREATED,}$1"; }

[ "$#" -le 1 ] || fail bad-args
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
DATE=$(date -u +%Y-%m-%d)

# shellcheck source=../render.sh
. "$HERE/../render.sh"

# <title> <body-file> -> the new issue's URL
create() {
  gh issue create --repo "$REPO" --title "$1" --body-file "$2" 2>/dev/null | tail -1
}

# The parent is filed first so the children can cite it, and its design is
# written once their URLs exist.
echo "This is a **tracking issue**; its design is written once its children are filed." \
  > "$TMP/parent.md"
PARENT=$(create "[set-review eval] Notes export" "$TMP/parent.md") || fail create-failed
filed "$PARENT" || fail create-failed

# <fixture-name> <title> -> the child's URL. The export child goes first, since
# the import child cites it.
child() {
  render "$FIX/child-$1.md" PARENT="$PARENT" CHILD_EXPORT="${EXPORT:-}" > "$TMP/$1.md"
  create "[set-review eval] $2" "$TMP/$1.md"
}
EXPORT=$(child export "Export script") || fail create-failed
filed "$EXPORT" || fail create-failed
CHECK=$(child check "Export checker") || fail create-failed
filed "$CHECK" || fail create-failed
IMPORT=$(child import "Import script") || fail create-failed
filed "$IMPORT" || fail create-failed

render "$FIX/parent.md" DATE="$DATE" CHILD_EXPORT="$EXPORT" CHILD_CHECK="$CHECK" \
  CHILD_IMPORT="$IMPORT" > "$TMP/parent.md"
gh issue edit "$PARENT" --repo "$REPO" --body-file "$TMP/parent.md" >/dev/null 2>&1 \
  || fail link-failed
gh issue edit "$PARENT" --repo "$REPO" --add-sub-issue "$EXPORT,$CHECK,$IMPORT" \
  >/dev/null 2>&1 || fail link-failed
gh issue edit "$IMPORT" --repo "$REPO" --add-blocked-by "$EXPORT" >/dev/null 2>&1 \
  || fail link-failed

echo "$PARENT"
echo "result=OK parent=$PARENT children=$EXPORT,$CHECK,$IMPORT"
