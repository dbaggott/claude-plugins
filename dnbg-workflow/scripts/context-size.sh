#!/usr/bin/env bash
# The size of the context this session's last request sent, for the
# orchestrator's restart trigger.
#
#   context-size.sh
#
# Prints exactly one line, then exits 0:
#   result=OK tokens=<n>
#   result=UNKNOWN reason=no-session-id|no-transcript|no-usage|parse
#
# <n> is input_tokens + cache_read_input_tokens + cache_creation_input_tokens
# from the `message.usage` of the transcript's last entry that has
# `type == "assistant"`, is not `isSidechain`, and carries a numeric
# `input_tokens`. An absent cache field counts 0. Any failure is UNKNOWN, never
# a guessed number: `no-session-id` an unset CLAUDE_CODE_SESSION_ID,
# `no-transcript` no transcript file for it, `no-usage` no such entry, `parse` a
# line that is not a JSON object.
#
# CLAUDE_CODE_SESSION_ID is documented (https://code.claude.com/docs/en/env-vars);
# the transcript's entry format is not, and changes between Claude Code versions
# (https://code.claude.com/docs/en/sessions), which is why every failure has a
# reason rather than a number. The transcript is found by glob rather than by
# computing the project slug, whose rule is undocumented; of several matches the
# most recently written is read.
#
# A subagent sees its parent's session ID, so run from one this reports the
# main session's size: it is for the orchestrator, not for an author.
set -euo pipefail

unknown() { echo "result=UNKNOWN reason=$1"; exit 0; }

[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || unknown no-session-id

shopt -s nullglob
MATCHES=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl)
shopt -u nullglob
[ "${#MATCHES[@]}" -gt 0 ] || unknown no-transcript
# shellcheck disable=SC2012  # The names are paths this script globbed, not input.
TRANSCRIPT=$(ls -t "${MATCHES[@]}" | head -n 1)

TOKENS=$(jq -n -r '
  reduce inputs as $e (null;
    if ($e | type) != "object" then error("not an object")
    elif $e.type == "assistant" and $e.isSidechain != true
         and (try $e.message.usage.input_tokens catch null | type) == "number"
    then $e.message.usage
    else . end)
  | if . == null then "none"
    else .input_tokens + (.cache_read_input_tokens // 0)
         + (.cache_creation_input_tokens // 0)
    end' "$TRANSCRIPT" 2>/dev/null) || unknown parse

case "$TOKENS" in
  none) unknown no-usage ;;
  ''|*[!0-9]*) unknown parse ;;
esac
echo "result=OK tokens=$TOKENS"
