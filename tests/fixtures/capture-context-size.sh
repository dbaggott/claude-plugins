#!/usr/bin/env bash
# Record the tail of this session's real transcript as context-size.sh's fixture.
#
#   capture-context-size.sh [<lines>]
#
# Run it from a Bash tool call in a Claude Code session. Writes
# tests/fixtures/context-size/transcript.jsonl: a `_captured` line naming the
# Claude Code version and date, then the transcript's last <lines> entries
# (default 14). Each entry is scrubbed to the fields context-size.sh reads,
# `type`, `isSidechain` and `message.usage`, so no prompt or tool output is
# committed. Re-take it after a Claude Code upgrade: the format is internal, and
# a fixture written by hand would match the script rather than the format. The
# fixture's token count is pinned in tests/context-size.bats, so set it there to
# the sum of the three input fields it prints for the last main-thread
# assistant entry.
set -euo pipefail

LINES="${1:-14}"
: "${CLAUDE_CODE_SESSION_ID:?run this from a Claude Code session}"
shopt -s nullglob
MATCHES=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl)
shopt -u nullglob
[ "${#MATCHES[@]}" -gt 0 ] || { echo "no transcript for session $CLAUDE_CODE_SESSION_ID" >&2; exit 1; }
# shellcheck disable=SC2012  # The names are paths this script globbed, not input.
SRC=$(ls -t "${MATCHES[@]}" | head -n 1)
OUT="$(cd "$(dirname "$0")" && pwd)/context-size/transcript.jsonl"
mkdir -p "$(dirname "$OUT")"

{
  jq -nc --arg v "$(claude --version)" --arg d "$(date -u +%F)" \
    '{_captured: {claude_code: $v, date: $d}}'
  tail -n "$LINES" "$SRC" | jq -c '
    {type}
    + (if has("isSidechain") then {isSidechain} else {} end)
    + (if (.message | type) == "object" and (.message | has("usage"))
       then {message: {usage: .message.usage}} else {} end)'
} > "$OUT"
echo "$OUT"
jq -c 'select(.type == "assistant" and .isSidechain != true) | .message.usage | {input_tokens, cache_read_input_tokens, cache_creation_input_tokens}' "$OUT" | tail -n 1
