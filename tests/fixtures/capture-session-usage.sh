#!/usr/bin/env bash
# Record a real session's transcripts as session-usage.sh's fixture.
#
#   capture-session-usage.sh [<session-id>]
#
# Reads the session's main transcript and every subagent transcript under it,
# by default this session's (CLAUDE_CODE_SESSION_ID); pick one with two or more
# subagents, at least one at spawn depth 2, so a `parent=<id>` is exercised.
# Writes, under tests/fixtures/session-usage/:
#
# - `main.jsonl` and `subagents/agent-<id>.jsonl`, each entry scrubbed to
#   `type`, `isSidechain`, `message.id` and `message.usage`, so no prompt,
#   command or tool output is committed;
# - `subagents/agent-<id>.meta.json`, kept to `agentType`, `spawnDepth` and
#   `parentAgentId`;
# - `captured.json`, naming the Claude Code version the session logged, the
#   capture date and each file's nonce.
#
# Each transcript then ends on a line this script writes rather than one the
# session logged, `{"type":"user","message":{"content":"<nonce>"}}`: main's
# nonce is usage-0000000000000000, a subagent's usage- and the last 16
# characters of its id. A real nonce sits in a tool result; the tests need one
# per file they can find.
#
# Re-take it after a Claude Code upgrade, since the format is internal. The
# counts it prints, per file, are pinned in tests/session-usage.bats.
set -euo pipefail

ID="${1:-${CLAUDE_CODE_SESSION_ID:?run this from a Claude Code session, or name one}}"
shopt -s nullglob
MATCHES=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$ID".jsonl)
shopt -u nullglob
[ "${#MATCHES[@]}" -gt 0 ] || { echo "no transcript for session $ID" >&2; exit 1; }
# shellcheck disable=SC2012  # The names are paths this script globbed, not input.
SRC=$(ls -t "${MATCHES[@]}" | head -n 1)
OUT="$(cd "$(dirname "$0")" && pwd)/session-usage"
rm -rf "$OUT"; mkdir -p "$OUT/subagents"

scrub() {  # <transcript> <nonce> > the scrubbed transcript
  jq -c '
    {type}
    + (if has("isSidechain") then {isSidechain} else {} end)
    + (if (.message | type) == "object" and (.message | has("id") or has("usage"))
       then {message: (.message | {id, usage} | with_entries(select(.value != null)))}
       else {} end)' "$1"
  jq -nc --arg n "$2" '{type: "user", message: {content: $n}}'
}

NONCES=$(jq -n '{main: "usage-0000000000000000"}')
scrub "$SRC" usage-0000000000000000 > "$OUT/main.jsonl"
shopt -s nullglob
for sub in "${SRC%.jsonl}"/subagents/agent-*.jsonl; do
  name=$(basename "$sub" .jsonl)
  nonce="usage-${name: -16}"
  [[ $nonce =~ ^usage-[0-9a-f]{16}$ ]] || { echo "$name: id is not hex" >&2; exit 1; }
  scrub "$sub" "$nonce" > "$OUT/subagents/$name.jsonl"
  jq '{agentType, spawnDepth, parentAgentId}' "${sub%.jsonl}.meta.json" > "$OUT/subagents/$name.meta.json"
  NONCES=$(jq --arg k "$name" --arg n "$nonce" '. + {($k): $n}' <<< "$NONCES")
done
shopt -u nullglob

VERSION=$(jq -r 'select((.version | type) == "string") | .version' "$SRC" | tail -n 1)
jq -n --arg v "$VERSION" --arg d "$(date -u +%F)" --argjson n "$NONCES" \
  '{claude_code: $v, date: $d, nonces: $n}' > "$OUT/captured.json"

# Each file's counts, worked independently of lib-usage.sh: first entry per id.
for f in "$OUT/main.jsonl" "$OUT"/subagents/*.jsonl; do
  jq -s -r --arg f "${f#"$OUT"/}" '
    [.[] | select(.type == "assistant" and .message.usage != null)]
    | group_by(.message.id) | map(.[0].message.usage)
    | "\($f) requests=\(length) input=\(map(.input_tokens // 0) | add // 0) cache_write=\(map(.cache_creation_input_tokens // 0) | add // 0) cache_read=\(map(.cache_read_input_tokens // 0) | add // 0) output=\(map(.output_tokens // 0) | add // 0)"' "$f"
done
