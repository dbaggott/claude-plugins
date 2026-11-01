#!/usr/bin/env bats
#
# Tests for the read of an agent's own usage from its transcript. The
# transcripts are the fixture tests/fixtures/capture-session-usage.sh took from
# a real session, copied under a CLAUDE_CONFIG_DIR of the test's own; each ends
# on a nonce line the capture wrote, named in the fixture's captured.json.

USAGE="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/session-usage.sh"
FIXTURE="${BATS_TEST_DIRNAME}/fixtures/session-usage"
ID=0b6c1e1a-1111-4222-8333-444455556666
MAIN_NONCE=usage-0000000000000000
SELF_NONCE=usage-7bee05399d9d6f22
# The fixture's counts, per transcript, as the capture printed them.
MAIN_COUNTS="requests=5 input=10 cache_write=17808 cache_read=99131 output=1543"
DEPTH1=a203bc81e0c8339ce
DEPTH1_COUNTS="requests=7 input=14 cache_write=33068 cache_read=147064 output=984"
DEPTH2=a7bee05399d9d6f22
DEPTH2_COUNTS="requests=3 input=6 cache_write=12363 cache_read=38032 output=207"
SESSION_COUNTS="requests=15 input=30 cache_write=63239 cache_read=284227 output=2734"

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export CLAUDE_CODE_SESSION_ID="$ID"
  PROJECT="$CLAUDE_CONFIG_DIR/projects/-Users-someone-git-repo"
  mkdir -p "$PROJECT/$ID"
  MAIN="$PROJECT/$ID.jsonl"
  SUBS="$PROJECT/$ID/subagents"
  cp "$FIXTURE/main.jsonl" "$MAIN"
  cp -R "$FIXTURE/subagents" "$SUBS"
}

nonce_line() {  # <nonce> -> a transcript line carrying it
  printf '{"type":"user","message":{"content":"%s"}}\n' "$1"
}

@test "the fixture's nonces are the ones captured.json names" {
  [ "$(jq -r .nonces.main "$FIXTURE/captured.json")" = "$MAIN_NONCE" ]
  [ "$(jq -r ".nonces[\"agent-$DEPTH2\"]" "$FIXTURE/captured.json")" = "$SELF_NONCE" ]
}

@test "--nonce prints a fresh nonce of the form the second call takes, and nothing else" {
  run "$USAGE" --nonce
  [ "$status" -eq 0 ]
  [[ $output =~ ^usage-[0-9a-f]{16}$ ]]
  local first=$output
  run "$USAGE" --nonce
  [ "$output" != "$first" ]
}

@test "a match in the main transcript is the session, with one child line per subagent" {
  run "$USAGE" "$MAIN_NONCE"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "result=OK scope=session agent=main $SESSION_COUNTS" ]
  [ "${lines[1]}" = "child=general-purpose id=$DEPTH1 depth=1 parent=session $DEPTH1_COUNTS" ]
  [ "${lines[2]}" = "child=general-purpose id=$DEPTH2 depth=2 parent=$DEPTH1 $DEPTH2_COUNTS" ]
}

@test "a match in a subagent transcript is that agent alone" {
  run "$USAGE" "$SELF_NONCE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK scope=self agent=general-purpose $DEPTH2_COUNTS" ]
}

@test "child lines sort by depth, then id" {
  local early=a0000000000000000
  cp "$SUBS/agent-$DEPTH2.jsonl" "$SUBS/agent-$early.jsonl"
  jq '.spawnDepth = 2' "$SUBS/agent-$DEPTH2.meta.json" > "$SUBS/agent-$early.meta.json"
  run "$USAGE" "$MAIN_NONCE"
  [ "${lines[1]}" = "child=general-purpose id=$DEPTH1 depth=1 parent=session $DEPTH1_COUNTS" ]
  [[ ${lines[2]} == "child=general-purpose id=$early depth=2 "* ]]
  [[ ${lines[3]} == "child=general-purpose id=$DEPTH2 depth=2 "* ]]
}

@test "entries sharing a message.id count once, at the first one's usage" {
  {
    echo '{"type":"assistant","isSidechain":true,"message":{"id":"msg_x","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}'
    echo '{"type":"assistant","isSidechain":true,"message":{"id":"msg_x","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":400}}}'
  } >> "$SUBS/agent-$DEPTH2.jsonl"
  run "$USAGE" "$SELF_NONCE"
  [ "$output" = "result=OK scope=self agent=general-purpose requests=4 input=7 cache_write=12365 cache_read=38035 output=211" ]
}

@test "an absent usage field counts zero" {
  echo '{"type":"assistant","message":{"id":"msg_y","usage":{"output_tokens":5}}}' >> "$SUBS/agent-$DEPTH2.jsonl"
  run "$USAGE" "$SELF_NONCE"
  [ "$output" = "result=OK scope=self agent=general-purpose requests=4 input=6 cache_write=12363 cache_read=38032 output=212" ]
}

@test "the nonce on several lines of one file is one match" {
  nonce_line "$SELF_NONCE" >> "$SUBS/agent-$DEPTH2.jsonl"
  nonce_line "$SELF_NONCE" >> "$SUBS/agent-$DEPTH2.jsonl"
  run "$USAGE" "$SELF_NONCE"
  [ "$output" = "result=OK scope=self agent=general-purpose $DEPTH2_COUNTS" ]
}

@test "the nonce in two files is ambiguous" {
  nonce_line "$SELF_NONCE" >> "$MAIN"
  run "$USAGE" "$SELF_NONCE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=ambiguous" ]
}

@test "a nonce no file holds is no-match" {
  run "$USAGE" usage-ffffffffffffffff
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-match" ]
}

@test "a missing argument, or one not of the nonce's form, is no-nonce" {
  run "$USAGE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-nonce" ]
  run "$USAGE" usage-0000
  [ "$output" = "result=UNKNOWN reason=no-nonce" ]
  run "$USAGE" '.*'
  [ "$output" = "result=UNKNOWN reason=no-nonce" ]
}

@test "no session id is unknown" {
  unset CLAUDE_CODE_SESSION_ID
  run "$USAGE" "$MAIN_NONCE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-session-id" ]
}

@test "no transcript for the session id is unknown" {
  rm "$MAIN"
  run "$USAGE" "$MAIN_NONCE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-transcript" ]
}

@test "a line that is not JSON is parse, not a number" {
  printf '{"type":"assistant","message":{"usage":{"input_tok\n' >> "$SUBS/agent-$DEPTH2.jsonl"
  run "$USAGE" "$SELF_NONCE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=parse" ]
}

@test "a bad line in a child transcript makes the session total parse" {
  echo '[1,2]' >> "$SUBS/agent-$DEPTH2.jsonl"
  run "$USAGE" "$MAIN_NONCE"
  [ "$output" = "result=UNKNOWN reason=parse" ]
}

@test "a non-numeric usage field is parse" {
  echo '{"type":"assistant","message":{"id":"msg_z","usage":{"input_tokens":"many"}}}' >> "$MAIN"
  run "$USAGE" "$MAIN_NONCE"
  [ "$output" = "result=UNKNOWN reason=parse" ]
}

@test "usage with no message.id is parse, since it cannot be deduplicated" {
  echo '{"type":"assistant","message":{"usage":{"input_tokens":1}}}' >> "$MAIN"
  run "$USAGE" "$MAIN_NONCE"
  [ "$output" = "result=UNKNOWN reason=parse" ]
}

@test "a matched subagent with no meta file is parse" {
  rm "$SUBS/agent-$DEPTH2.meta.json"
  run "$USAGE" "$SELF_NONCE"
  [ "$output" = "result=UNKNOWN reason=parse" ]
}
