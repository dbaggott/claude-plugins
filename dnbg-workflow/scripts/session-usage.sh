#!/usr/bin/env bash
# The usage of the calling agent's own run, for its retrospective at close-out.
#
#   session-usage.sh --nonce      prints a fresh nonce, usage-<16 hex>, and nothing else
#   session-usage.sh <nonce>      prints the usage of the transcript that holds it
#
# Run the two from two separate Bash calls, the second given the first's
# output. A running call is not in the transcript until it returns, so only the
# first call's output can be found by the second; and a dispatched agent sees
# its parent's CLAUDE_CODE_SESSION_ID, so the nonce, not the session id, is
# what tells the agent's own transcript from its parent's.
#
# The second call prints one result line, then exits 0:
#   result=OK scope=session agent=main requests=<n> input=<n> cache_write=<n> cache_read=<n> output=<n>
#   result=OK scope=self agent=<agentType> requests=<n> input=<n> cache_write=<n> cache_read=<n> output=<n>
#   result=UNKNOWN reason=no-session-id|no-transcript|no-nonce|no-match|ambiguous|parse
#
# It greps `<config>/projects/*/<session-id>.jsonl`, the session's main
# transcript, and every `<session-id>/subagents/*.jsonl` beside it, and goes on
# only when exactly one file holds the nonce; several lines of one file are one
# match, since a transcript repeats a tool result in later entries. `<config>`
# is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}.
#
# - Found in the main transcript: `scope=session agent=main`. The counts total
#   the main transcript and every subagent transcript under it, at every depth.
#   Then one line per subagent transcript, sorted by depth and then id:
#     child=<agentType> id=<agent id> depth=<spawnDepth> parent=<parentAgentId|session> requests=<n> input=<n> cache_write=<n> cache_read=<n> output=<n>
#   read from its `agent-<id>.meta.json`, with `parent=session` where the meta
#   file names no parent, as a depth-1 one does not.
# - Found under `subagents/`: `scope=self` with that meta file's `agentType`,
#   counting that transcript alone, and no child lines.
#
# The counts are lib-usage.sh's, per transcript, summed with no dedup across
# files: a subagent's entries live in its own file, and the main transcripts
# observed carry no sidechain assistant entries that could repeat them.
#
# `no-nonce` is an argument missing or not of the nonce's form; `no-match` no
# file holding it; `ambiguous` several; `parse` a transcript lib-usage.sh
# cannot read, or a matched or child meta file with no string `agentType`, no
# integer `spawnDepth`, or that is not JSON. Every failure is UNKNOWN, never a
# guessed number.
set -euo pipefail

# shellcheck source=./lib-usage.sh
. "$(dirname "$0")/lib-usage.sh"

unknown() { echo "result=UNKNOWN reason=$1"; exit 0; }

if [ "${1:-}" = --nonce ]; then
  echo "usage-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  exit 0
fi

NONCE=${1:-}
[[ $NONCE =~ ^usage-[0-9a-f]{16}$ ]] || unknown no-nonce
[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || unknown no-session-id

shopt -s nullglob
MAINS=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl)
[ "${#MAINS[@]}" -gt 0 ] || unknown no-transcript
FILES=()
for main in "${MAINS[@]}"; do
  FILES+=("$main" "${main%.jsonl}"/subagents/*.jsonl)
done
shopt -u nullglob

HITS=()
while IFS= read -r f; do HITS+=("$f"); done < <(grep -lF -- "$NONCE" "${FILES[@]}" || true)
[ "${#HITS[@]}" -gt 0 ] || unknown no-match
[ "${#HITS[@]}" -eq 1 ] || unknown ambiguous
HIT=${HITS[0]}
SCOPE=self
for main in "${MAINS[@]}"; do [ "$HIT" != "$main" ] || SCOPE=session; done

counts() {  # <transcript> -> its five counts, space-separated, or exits parse
  local line
  line=$(usage_tally "$1")
  [[ $line == "result=OK "* ]] || return 1
  local kv out=()
  for kv in ${line#result=OK }; do out+=("${kv#*=}"); done
  echo "${out[*]}"
}

meta() {  # <transcript> -> its meta file's agentType, spawnDepth and parent, tab-separated
  jq -e -r '
    select((.agentType | type) == "string" and (.agentType | test("^[^\\s=]+$"))
           and (.spawnDepth | type) == "number" and .spawnDepth == (.spawnDepth | floor))
    | [.agentType, .spawnDepth, (.parentAgentId // "session")] | @tsv
  ' "${1%.jsonl}.meta.json" 2>/dev/null
}

fields() {  # <r> <i> <cw> <cr> <o> -> the counts as result-line fields
  echo "requests=$1 input=$2 cache_write=$3 cache_read=$4 output=$5"
}

if [ "$SCOPE" = self ]; then
  m=$(meta "$HIT") || unknown parse
  c=$(counts "$HIT") || unknown parse
  # shellcheck disable=SC2086  # the counts are five words by construction
  echo "result=OK scope=self agent=${m%%$'\t'*} $(fields $c)"
  exit 0
fi

c=$(counts "$HIT") || unknown parse
read -r R I CW CR O <<< "$c"
CHILDREN=()
shopt -s nullglob
for sub in "${HIT%.jsonl}"/subagents/*.jsonl; do
  m=$(meta "$sub") || unknown parse
  c=$(counts "$sub") || unknown parse
  read -r r i cw cr o <<< "$c"
  R=$((R + r)); I=$((I + i)); CW=$((CW + cw)); CR=$((CR + cr)); O=$((O + o))
  IFS=$'\t' read -r agent depth parent <<< "$m"
  id=$(basename "$sub" .jsonl); id=${id#agent-}
  CHILDREN+=("$depth"$'\t'"$id"$'\t'"child=$agent id=$id depth=$depth parent=$parent $(fields "$r" "$i" "$cw" "$cr" "$o")")
done
shopt -u nullglob

echo "result=OK scope=session agent=main $(fields "$R" "$I" "$CW" "$CR" "$O")"
[ "${#CHILDREN[@]}" -eq 0 ] || printf '%s\n' "${CHILDREN[@]}" | sort -t $'\t' -k1,1n -k2,2 | cut -f3
