#!/usr/bin/env bash
# Append rows to a table, or bullets to a list, under one heading of an issue's
# body — a tracking issue's decision log or findings log — or set the last
# (State) cell of rows the table already holds.
#
#   log-row.sh <owner/repo> <n> --table=<heading>  --row='| … |' [--row=…] [--as=<role>]
#   log-row.sh <owner/repo> <n> --bullet=<heading> --text='…'    [--text=…] [--as=<role>]
#   log-row.sh <owner/repo> <n> --table=<heading>  --set-state=proposed|decided|applied \
#     --row='| … |' [--row=…] [--as=<role>]
#
# The section is the heading whose text is exactly <heading>, at any level, down
# to the next heading of the same or a higher level; a heading inside a code
# fence is not one. A row goes after the section's last table line, a bullet
# (`- <text>`) after its last non-blank line, set off by a blank line when that
# line is not part of a list. Prints exactly one result line, then exits 0:
#   result=OK appended=<k> body_edited=<iso|none> body_chars=<n>
#   result=OK updated=<k> body_edited=<iso|none> body_chars=<n>        (--set-state)
#   result=ERROR reason=bad-args|unsupported-forge|issue-query|section-missing|table-missing|write|write-lost|role now=<iso>
#   result=ERROR reason=row-missing body_edited=<iso|none> now=<iso>   (--set-state)
#
# A line the section already holds outside a code fence is not appended again,
# nor is one given twice, so `appended` can be less than the lines given, and
# re-running a call whose outcome is unknown is safe. `body_chars` is the body's
# length after the write, the figure the tracking issue's archive threshold is
# measured against.
#
# `--set-state` takes each `--row` as the row reads now, matched as a whole line
# by the same rules, and replaces only the text of its last cell with the state,
# keeping the cell's spacing (one space each side when the cell holds none) and
# every other byte. Every line matching a given
# row changes, and `updated` counts the lines this run changed. A given row whose
# last cell already reads the state is done, so a re-run is safe here too.
# `row-missing` means a given row is in the section in neither its given state
# nor the target one: nothing is written when the first read shows it, and when
# a later read does, after a write landed, `body_edited` is that read's.
#
# Body writes replace the whole body, so a concurrent writer can replace this
# one. Each write is confirmed by fetching the body again, and lines found
# missing are appended to the new body, or rows found in their given state set
# again, up to MAX_WRITES writes; `write-lost` means some were still undone
# after the last.
#
# `--as=<role>` makes the reads and writes under that role, through one
# `as-role.sh` call, so a role mints once for the whole run. The OK line then
# ends with `as=<login>`, plus `fallback=unconfigured` when the role ran as the
# operator. `role` means the resolver refused; its stderr says why, and nothing
# was read or written. Without `--as` the script runs as the operator, as it
# always has, and its output is unchanged.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail
# `--under-role` is this script's own re-run under the resolver (`--as`, below),
# which keeps the role's token the resolver put in place. Not for callers.
UNDER_ROLE=0
if [ "${1:-}" = --under-role ]; then UNDER_ROLE=1; shift; fi
[ "$UNDER_ROLE" = 1 ] || unset GH_TOKEN
# shellcheck source=./lib-role.sh
. "$(dirname "$0")/lib-role.sh"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO="${1:-}"; N="${2:-}"
[ "$#" -ge 2 ] || fail bad-args
shift 2
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|0*|*[!0-9]*) fail bad-args ;; esac

MODE=""; HEADING=""; LINES=(); AS=""; ARGS=(); STATE=""
for a in "$@"; do
  case "$a" in
    --as=?*) AS="${a#--as=}"; continue ;;
    --set-state=*)
      [ -z "$STATE" ] || fail bad-args
      STATE="${a#--set-state=}"
      case "$STATE" in proposed|decided|applied) ;; *) fail bad-args ;; esac ;;
    --table=*|--bullet=*)
      [ -z "$MODE" ] || fail bad-args
      MODE="${a%%=*}"; MODE="${MODE#--}"; HEADING="${a#*=}" ;;
    --row=*)  [ "$MODE" = table ]  || fail bad-args; LINES+=("${a#--row=}") ;;
    --text=*) [ "$MODE" = bullet ] || fail bad-args; LINES+=("- ${a#--text=}") ;;
    *) fail bad-args ;;
  esac
  ARGS+=("$a")
done
[ -n "$HEADING" ] && [ "${#LINES[@]}" -gt 0 ] || fail bad-args
[ -z "$STATE" ] || [ "$MODE" = table ] || fail bad-args
NL=$'\n'; CR=$'\r'
for l in "${LINES[@]}"; do
  case "$l" in *"$NL"*|*"$CR"*) fail bad-args ;; esac
  [ "$MODE" = bullet ] || case "$l" in '|'*'|') ;; *) fail bad-args ;; esac
done

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

if [ -n "$AS" ]; then
  # This script again, under the role. The resolver's own line,
  # `as-role.sh: result=…`, comes on stderr and is read here; the inner run's
  # result line is the one stdout line, and anything else passes on to stderr.
  OUT=$("$(dirname "$0")/as-role.sh" "$AS" "$REPO" -- \
        bash "$0" --under-role "$REPO" "$N" "${ARGS[@]}" 2>&1) || true
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
    result=OK\ *) echo "$RESULT$TAIL" ;;
    result=ERROR\ *) echo "$RESULT" ;;
    *) fail write ;;
  esac
  exit 0
fi

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"
MAX_WRITES=${MAX_WRITES:-3}

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
printf '%s\n' "${LINES[@]}" > "$WORK/lines"
# The row with its last cell's text replaced by the state, the cell's leading
# and trailing spaces kept.
with_state() {
  local row="${1%|}" cell lead trail
  cell="${row##*|}"; row="${row%|*}"
  lead="${cell%%[![:space:]]*}"; trail="${cell##*[![:space:]]}"
  [ "$lead" != "$cell" ] || { lead=" "; trail=" "; }
  printf '%s|%s%s%s|\n' "$row" "$lead" "$STATE" "$trail"
}
: > "$WORK/targets"
if [ -n "$STATE" ]; then for l in "${LINES[@]}"; do with_state "$l" >> "$WORK/targets"; done; fi

# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='query($owner:String!, $repo:String!, $n:Int!) {
  repository(owner: $owner, name: $repo) { issue(number: $n) { body lastEditedAt } }
}'

# The body goes to a file rather than a variable: `$(…)` strips trailing
# newlines, and the write would then change text this script never meant to.
fetch() {
  local raw
  raw=$(gh api graphql -f query="$Q" -f owner="$OWNER" -f repo="$NAME" -F n="$N" 2>/dev/null) || true
  printf '%s' "$raw" | jq -je '.data.repository.issue.body | strings' > "$WORK/body" 2>/dev/null \
    || fail issue-query
  read -r EDITED CHARS < <(printf '%s' "$raw" |
    jq -r '.data.repository.issue | "\(.lastEditedAt // "none") \(.body | length)"')
}

# Writes the body with the missing lines inserted, or under --set-state the
# rows' states set, to "$WORK/new", and the count of lines it inserted or
# changed to "$WORK/count". A CRLF body keeps CRLF on those lines, and a body
# with no final newline gains none.
merge() {
  local rc=0 trail=0
  [ -z "$(tail -c1 "$WORK/body")" ] && [ -s "$WORK/body" ] && trail=1
  HEADING="$HEADING" awk -v mode="$MODE" -v trail="$trail" -v setstate="${STATE:+1}" \
    -v lines="$WORK/lines" -v targets="$WORK/targets" -v count="$WORK/count" '
    BEGIN {
      heading = ENVIRON["HEADING"]
      while ((getline l < lines) > 0) add[++na] = l
      while ((getline l < targets) > 0) to[++nt] = l
    }
    { raw[NR] = $0; p = $0; sub(/\r$/, "", p); plain[NR] = p; cr[NR] = (p == $0) ? "" : "\r" }
    END {
      # A fence closes only on its own character, so ~~~ inside ``` stays code.
      fc = ""
      for (i = 1; i <= NR; i++) {
        p = plain[i]; sub(/^ ? ? ?/, "", p)
        if (fc == "" && p ~ /^(```|~~~)/) { fc = substr(p, 1, 1); code[i] = 1; continue }
        if (fc != "") { code[i] = 1; if (index(p, fc fc fc) == 1) fc = ""; continue }
      }
      start = 0; stop = NR + 1
      for (i = 1; i <= NR; i++) {
        p = plain[i]
        if (code[i] || p !~ /^#+[ \t]/) continue
        lvl = match(p, /[^#]/) - 1
        if (lvl > 6) continue
        t = substr(p, lvl + 1); sub(/^[ \t]+/, "", t); sub(/[ \t]+#*[ \t]*$/, "", t)
        if (start) { if (lvl <= slvl) { stop = i; break } }
        else if (t == heading) { start = i; slvl = lvl }
      }
      if (!start) exit 3
      anchor = 0
      for (i = start + 1; i < stop; i++) {
        if (mode == "bullet" && plain[i] !~ /^[ \t]*$/) anchor = i
        if (code[i]) continue
        if (mode == "table" && plain[i] ~ /^ *\|/) anchor = i
        for (j = 1; j <= na; j++) if (plain[i] == add[j]) have[j] = 1
      }
      if (!anchor && mode == "table") exit 4
      if (setstate) {
        k = 0
        for (i = start + 1; i < stop; i++) {
          if (code[i]) continue
          for (j = 1; j <= na; j++) {
            if (plain[i] == to[j]) { done[j] = 1; continue }
            if (plain[i] != add[j]) continue
            done[j] = 1
            if (!(i in setto)) { setto[i] = to[j] cr[i]; k++ }
          }
        }
        for (j = 1; j <= na; j++) if (!done[j]) exit 5
        for (i = 1; i <= NR; i++) printf "%s%s", (i in setto) ? setto[i] : raw[i], (i < NR || trail) ? "\n" : ""
        print k > count
        exit 0
      }
      if (!anchor) anchor = start
      # A first bullet under the heading or under prose starts its own block.
      lead = mode == "bullet" && (anchor == start || plain[anchor] !~ /^([-*+][ \t]|[ \t])/)
      k = 0; no = 0
      for (i = 1; i <= anchor; i++) out[++no] = raw[i]
      for (j = 1; j <= na; j++) {
        if (have[j]) continue
        if (lead && !k) out[++no] = cr[anchor]
        out[++no] = add[j] cr[anchor]; k++
        for (m = j + 1; m <= na; m++) if (add[m] == add[j]) have[m] = 1
      }
      for (i = anchor + 1; i <= NR; i++) out[++no] = raw[i]
      for (i = 1; i <= no; i++) printf "%s%s", out[i], (i < no || trail) ? "\n" : ""
      print k > count
    }' "$WORK/body" > "$WORK/new" || rc=$?
  case "$rc" in
    0) ;; 3) fail section-missing ;; 4) fail table-missing ;;
    5) echo "result=ERROR reason=row-missing body_edited=$EDITED now=$(now_iso)"; exit 0 ;;
    *) fail issue-query ;;
  esac
  K=$(cat "$WORK/count")
}

fetch; merge
DONE=$K
writes=0
while [ "$K" != 0 ]; do
  [ "$writes" -lt "$MAX_WRITES" ] || fail write-lost
  gh issue edit "$N" --repo "$REPO" --body-file "$WORK/new" >/dev/null 2>&1 || fail write
  writes=$((writes + 1))
  fetch; merge
done

VERB=appended; [ -z "$STATE" ] || VERB=updated
echo "result=OK $VERB=$DONE body_edited=$EDITED body_chars=$CHARS"
