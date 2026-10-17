#!/usr/bin/env bash
# Record every forge answer one issue-stage.sh run reads, as a fixture.
#
#   capture-issue-stage.sh <owner/repo> <n> <fixture-name> [--slug=<login>]
#                          [--edit='<key>=<jq filter>' ...]
#
# Writes tests/fixtures/issue-stage/<fixture-name>.json: `calls`, each answer
# keyed by issue-stage-calls.bash, and `_captured`, naming the issue, the time and
# the line the live run printed. tests/issue-stage.bats replays `calls` through a
# stubbed `gh`, so the composition is exercised against what GitHub returned.
#
# A stage no live issue is in is derived from a recording with `--edit`: the
# filter rewrites the answer to the call `<key>` names before the run reads it,
# so the run goes down the edited path and records what it read there. The
# fixture lists each edit in `_edited`, so nobody re-takes it expecting the live
# state to match.
set -euo pipefail

usage() {
  echo "usage: capture-issue-stage.sh <owner/repo> <n> <fixture-name> [--slug=<login>] [--edit='<key>=<jq filter>' ...]" >&2
  exit 2
}
REPO="${1:-}"; N="${2:-}"; NAME="${3:-}"
[ -n "$REPO" ] && [ -n "$N" ] && [ -n "$NAME" ] || usage
shift 3
SLUG_ARG=""; EDITS='{}'
for a in "$@"; do
  case "$a" in
    --slug=*) SLUG_ARG="$a" ;;
    --edit=*=*) a="${a#--edit=}"
                EDITS=$(jq -c --arg k "${a%%=*}" --arg f "${a#*=}" '. + {($k): $f}' <<<"$EDITS") ;;
    *) usage ;;
  esac
done
case "$NAME" in *[!a-z0-9-]*) echo "fixture name: lowercase, digits, dashes" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/issue-stage/$NAME.json"
mkdir -p "$HERE/issue-stage"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
printf '%s' "$EDITS" > "$WORK/edits.json"
REAL_GH=$(command -v gh)
cat > "$WORK/bin/gh" <<SHIM
#!/usr/bin/env bash
. "$HERE/issue-stage-calls.bash"
key=\$(issue_stage_call_key "\$@")
set +e
out=\$("$REAL_GH" "\$@" 2>/dev/null); code=\$?
set -e
filter=\$(jq -r --arg k "\$key" '.[\$k] // empty' "$WORK/edits.json")
if [ -n "\$filter" ]; then
  out=\$(jq -c "\$filter" <<<"\$out") || { echo "edit for \$key did not apply" >&2; exit 97; }
fi
jq -nc --arg k "\$key" --arg o "\$out" --argjson c "\$code" '{key: \$k, out: \$o, exit: \$c}' >> "$WORK/calls.jsonl"
printf '%s' "\$out"
exit \$code
SHIM
chmod +x "$WORK/bin/gh"
: > "$WORK/calls.jsonl"

# An unset session id, as in the replay, so a claim this session made reads FOREIGN
# in both.
LINE=$(env -u CLAUDE_CODE_SESSION_ID PATH="$WORK/bin:$PATH" \
  "$HERE/../../dnbg-workflow/scripts/issue-stage.sh" "$REPO" "$N" ${SLUG_ARG:+"$SLUG_ARG"})

jq -s --arg r "$REPO" --arg n "$N" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg line "$LINE" '
  {_captured: {repo: $r, issue: ($n | tonumber), at: $at, output: $line}}
  + (if $edits == {} then {} else {_edited: ($edits | to_entries | map("\(.key): \(.value)"))} end)
  + {calls: (map({(.key): {out, exit}}) | add // {})}' \
  --argjson edits "$EDITS" "$WORK/calls.jsonl" > "$OUT"

echo "wrote $OUT"
echo "  $LINE"
