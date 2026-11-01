#!/usr/bin/env bash
# Post one decision-log row as a comment on an issue, in the shape
# skills/orchestrate/references/triage.md, "The row", gives, and optionally
# append the parent tracking issue's decision-log table row that links it.
#
#   decision-row.sh <owner/repo> <n> --id=<ID> --state=proposed|decided|applied \
#     --question=<text> --answer=<text> --basis=<text> \
#     [--parent=<parent issue URL> [--entry=<text>] [--table-state=<state>]] \
#     --as=<role>
#
# The comment reads, with no trailing newline:
#   Decision log: <ID> — <state>
#
#   **Question:** <question>
#   **Answer:** <answer>
#   **Basis:** <basis>
#
# `--parent` appends, through `log-row.sh --table="Decision log" --as=<role>`,
#   | <date> | <ID> | <child> | <entry> (<comment URL>) | <table state> |
# where <child> is https://github.com/<owner/repo>/issues/<n>, or `—` when that
# issue is the parent itself; <entry> is `--entry`, else the answer, with each
# `|` escaped as `\|`; <table state> is `--table-state`, else `--state`; and
# <date> is the comment's UTC creation date.
#
# Prints exactly one result line, then exits 0:
#   result=OK comment=<url> parent=<OK|none> as=<login>[ fallback=unconfigured]
#   result=ERROR reason=bad-args|unsupported-forge|role|comment now=<iso>
#   result=ERROR reason=parent-<log-row reason> comment=<url> now=<iso>
#
# A re-run is safe: a comment on the issue whose body is identical to the row,
# from any author, is reused rather than posted again, and `log-row.sh` skips a
# table row the section already holds. The row's date comes from the comment,
# so a re-run on a later day appends nothing new either. `comment` means
# listing the issue's comments or posting the row failed, so the outcome is
# unknown; `role` means the resolver refused and nothing was read or written.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail
# `--under-role <owner/repo> <n> <body file>` is this script's own re-run under
# the resolver, which keeps the role's token in place. Not for callers.
UNDER_ROLE=0
if [ "${1:-}" = --under-role ]; then UNDER_ROLE=1; shift; fi
[ "$UNDER_ROLE" = 1 ] || unset GH_TOKEN
# shellcheck source=./lib-role.sh
. "$(dirname "$0")/lib-role.sh"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

# The comment step, under the role: reuse an identical comment, or post one.
# Prints `result=OK comment=<url> date=<YYYY-MM-DD>`.
if [ "$UNDER_ROLE" = 1 ]; then
  REPO="$1"; N="$2"; FILE="$3"
  # GitHub keeps a comment's body as posted, but compare without CRs and
  # trailing whitespace so a normalized copy still counts as the same row.
  # shellcheck disable=SC2016  # jq program, not shell.
  FOUND=$(gh api --paginate "repos/$REPO/issues/$N/comments" 2>/dev/null |
    jq -rn --rawfile want "$FILE" '
      def norm: gsub("\r"; "") | sub("\\s+$"; "");
      ($want | norm) as $w
      | [inputs[] | select((.body // "") | norm == $w)] | first
      | if . == null then "" else "\(.html_url) \(.created_at[0:10])" end') \
    || fail comment
  if [ -n "$FOUND" ]; then
    echo "result=OK comment=${FOUND% *} date=${FOUND##* }"
    exit 0
  fi
  DATE=$(date -u +%Y-%m-%d)
  URL=$(gh issue comment "$N" --repo "$REPO" --body-file "$FILE" 2>/dev/null |
    grep -E '^https://' | tail -n1) || fail comment
  [ -n "$URL" ] || fail comment
  echo "result=OK comment=$URL date=$DATE"
  exit 0
fi

REPO="${1:-}"; N="${2:-}"
[ "$#" -ge 2 ] || fail bad-args
shift 2
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|0*|*[!0-9]*) fail bad-args ;; esac

ID=""; STATE=""; QUESTION=""; ANSWER=""; BASIS=""; PARENT=""; ENTRY=""
TABLE_STATE=""; AS=""; SEEN=" "
for a in "$@"; do
  case "$a" in --*=*) ;; *) fail bad-args ;; esac
  flag="${a%%=*}"; val="${a#*=}"
  case "$SEEN" in *" $flag "*) fail bad-args ;; esac
  SEEN="$SEEN$flag "
  case "$flag" in
    --id) ID="$val" ;;
    --state) STATE="$val" ;;
    --question) QUESTION="$val" ;;
    --answer) ANSWER="$val" ;;
    --basis) BASIS="$val" ;;
    --parent) PARENT="$val" ;;
    --entry) ENTRY="$val" ;;
    --table-state) TABLE_STATE="$val" ;;
    --as) AS="$val" ;;
    *) fail bad-args ;;
  esac
done
for v in "$ID" "$STATE" "$QUESTION" "$ANSWER" "$BASIS" "$AS"; do [ -n "$v" ] || fail bad-args; done
NL=$'\n'; CR=$'\r'
for v in "$ID" "$QUESTION" "$ANSWER" "$BASIS" "$ENTRY"; do
  case "$v" in *"$NL"*|*"$CR"*) fail bad-args ;; esac
done
valid_state() { case "$1" in proposed|decided|applied) ;; *) return 1 ;; esac; }
valid_state "$STATE" || fail bad-args
if [ -z "$PARENT" ]; then
  case "$SEEN" in *" --entry "*|*" --table-state "*) fail bad-args ;; esac
else
  [ -n "$ENTRY" ] || ENTRY="$ANSWER"
  [ -n "$TABLE_STATE" ] || TABLE_STATE="$STATE"
  valid_state "$TABLE_STATE" || fail bad-args
fi

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge
if [ -n "$PARENT" ]; then
  [[ "$PARENT" =~ ^https://github\.com/([^/]+/[^/]+)/issues/([1-9][0-9]*)$ ]] || fail bad-args
  PARENT_REPO="${BASH_REMATCH[1]}"; PARENT_N="${BASH_REMATCH[2]}"
fi

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
printf 'Decision log: %s — %s\n\n**Question:** %s\n**Answer:** %s\n**Basis:** %s' \
  "$ID" "$STATE" "$QUESTION" "$ANSWER" "$BASIS" > "$WORK/body"

# The resolver's own line, `as-role.sh: result=…`, comes on stderr and is read
# here; the inner run's result line is the one stdout line, and anything else
# passes on to stderr.
OUT=$("$(dirname "$0")/as-role.sh" "$AS" "$REPO" -- \
      bash "$0" --under-role "$REPO" "$N" "$WORK/body" 2>&1) || true
RESULT=""; TAIL=""; REFUSED=0
while IFS= read -r line; do
  case "$line" in
    result=*) RESULT="$line" ;;
    "as-role.sh: result=OK "*) TAIL=$(role_as_tail "$line") ;;
    "as-role.sh: result=ERROR "*) REFUSED=1 ;;
    '') ;;
    *) printf '%s\n' "$line" >&2 ;;
  esac
done <<<"$OUT"
[ "$REFUSED" = 0 ] || fail role
case "$RESULT" in
  "result=OK comment="*" date="*) ;;
  result=ERROR\ *) echo "$RESULT"; exit 0 ;;
  *) fail comment ;;
esac
COMMENT="${RESULT#result=OK comment=}"; COMMENT="${COMMENT% date=*}"
DATE="${RESULT##* date=}"

if [ -z "$PARENT" ]; then
  echo "result=OK comment=$COMMENT parent=none$TAIL"
  exit 0
fi

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
CHILD="https://github.com/$REPO/issues/$N"
[ "$(lower "$PARENT_REPO") $PARENT_N" != "$(lower "$REPO") $N" ] || CHILD="—"
ROW="| $DATE | $ID | $CHILD | ${ENTRY//|/\\|} ($COMMENT) | $TABLE_STATE |"
LOGGED=$("$(dirname "$0")/log-row.sh" "$PARENT_REPO" "$PARENT_N" \
  --table="Decision log" --row="$ROW" --as="$AS") || true
case "$LOGGED" in
  "result=OK "*) echo "result=OK comment=$COMMENT parent=OK$TAIL" ;;
  "result=ERROR reason="*)
    reason="${LOGGED#result=ERROR reason=}"; reason="${reason%% *}"
    echo "result=ERROR reason=parent-$reason comment=$COMMENT now=$(now_iso)" ;;
  *) echo "result=ERROR reason=parent-write comment=$COMMENT now=$(now_iso)" ;;
esac
