#!/usr/bin/env bats
#
# Tests for the read of this session's context size from its transcript. The
# transcript is the fixture tests/fixtures/capture-context-size.sh took from a
# real session, under a CLAUDE_CONFIG_DIR of the test's own.

SIZE="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/context-size.sh"
FIXTURE="${BATS_TEST_DIRNAME}/fixtures/context-size/transcript.jsonl"
# The fixture's last main-thread assistant entry: input + cache read + cache creation.
FIXTURE_TOKENS=72549
ID=0b6c1e1a-1111-4222-8333-444455556666

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export CLAUDE_CODE_SESSION_ID="$ID"
  PROJECT="$CLAUDE_CONFIG_DIR/projects/-Users-someone-git-repo"
  mkdir -p "$PROJECT"
  TRANSCRIPT="$PROJECT/$ID.jsonl"
  cp "$FIXTURE" "$TRANSCRIPT"
}

@test "a real transcript reads as its last assistant entry's three input fields" {
  run "$SIZE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK tokens=$FIXTURE_TOKENS" ]
}

@test "a sidechain assistant entry after the main thread's is not read" {
  echo '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":9,"cache_read_input_tokens":900000}}}' >> "$TRANSCRIPT"
  run "$SIZE"
  [ "$output" = "result=OK tokens=$FIXTURE_TOKENS" ]
}

@test "an assistant entry with no usage is passed over for the one before it" {
  echo '{"type":"assistant","isSidechain":false,"message":{"content":[]}}' >> "$TRANSCRIPT"
  run "$SIZE"
  [ "$output" = "result=OK tokens=$FIXTURE_TOKENS" ]
}

@test "an absent cache field counts zero" {
  echo '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":1234}}}' >> "$TRANSCRIPT"
  run "$SIZE"
  [ "$output" = "result=OK tokens=1234" ]
}

@test "of two transcripts for the session, the most recently written is read" {
  OTHER="$CLAUDE_CONFIG_DIR/projects/-Users-someone-elsewhere"
  mkdir -p "$OTHER"
  echo '{"type":"assistant","message":{"usage":{"input_tokens":5}}}' > "$OTHER/$ID.jsonl"
  touch -t 202001010000 "$OTHER/$ID.jsonl"
  run "$SIZE"
  [ "$output" = "result=OK tokens=$FIXTURE_TOKENS" ]
  touch "$OTHER/$ID.jsonl"
  run "$SIZE"
  [ "$output" = "result=OK tokens=5" ]
}

@test "no session id is unknown" {
  unset CLAUDE_CODE_SESSION_ID
  run "$SIZE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-session-id" ]
}

@test "no transcript for the session id is unknown" {
  rm "$TRANSCRIPT"
  run "$SIZE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-transcript" ]
}

@test "a transcript with no main-thread assistant usage is unknown" {
  grep -v '"type":"assistant"' "$FIXTURE" > "$TRANSCRIPT"
  echo '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":9}}}' >> "$TRANSCRIPT"
  run "$SIZE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-usage" ]
}

@test "malformed JSON is unknown, not a number" {
  printf '{"type":"assistant","message":{"usage":{"input_tok\n' >> "$TRANSCRIPT"
  run "$SIZE"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=parse" ]
}

@test "a line that is JSON but not an object is unknown" {
  echo '[1,2]' >> "$TRANSCRIPT"
  run "$SIZE"
  [ "$output" = "result=UNKNOWN reason=parse" ]
}

@test "a non-numeric cache field is unknown, not a number" {
  echo '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_read_input_tokens":"many"}}}' >> "$TRANSCRIPT"
  run "$SIZE"
  [ "$output" = "result=UNKNOWN reason=parse" ]
}
