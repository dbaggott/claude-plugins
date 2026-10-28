#!/usr/bin/env bats
#
# scripts/dev/test.sh is how CONTRIBUTING has a contributor, usually an agent,
# run the suite locally. What it promises is that its exit status and its last
# line are bats' own status, and that the full output is kept in a file it
# names, so a failure can be read without re-running the suite.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/dev/test.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/test-sh"
  export TMPDIR="$BATS_TEST_TMPDIR"
}

@test "test.sh: a failing test makes it exit with bats' status, named on the last line" {
  run "$SCRIPT" "$FIXTURES/failing.bats"
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "status=1" ]
}

@test "test.sh: stdout carries the plan, the failure and its diagnostics, not the passes" {
  run "$SCRIPT" "$FIXTURES/failing.bats"
  [ "${lines[0]}" = "1..2" ]
  [[ "$output" == *"not ok 2 fixture: fails"* ]]
  [[ "$output" == *"fixture diagnostic"* ]]
  [[ "$output" != *"ok 1 fixture: passes"* ]]
}

@test "test.sh: the file it names holds the full TAP output" {
  run "$SCRIPT" "$FIXTURES/failing.bats"
  tap_line=$(printf '%s\n' "${lines[@]}" | grep '^tap=')
  tap=${tap_line#tap=}
  grep -qx 'ok 1 fixture: passes' "$tap"
  grep -q '^not ok 2 fixture: fails' "$tap"
}

@test "test.sh: a passing run exits 0 with status=0 last" {
  run "$SCRIPT" "$FIXTURES/passing.bats"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "status=0" ]
  [[ "$output" != *"not ok"* ]]
}
