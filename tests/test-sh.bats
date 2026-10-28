#!/usr/bin/env bats
#
# scripts/dev/test.sh is how CONTRIBUTING has a contributor, usually an agent,
# run the suite locally. What it promises is that its exit status and its last
# line are bats' own status, that stdout names every failure, skip and error,
# and that the full output is kept in a file it names, so a failure can be read
# without re-running the suite.

setup_file() {
  export SCRIPT="$BATS_TEST_DIRNAME/../scripts/dev/test.sh"
  export FIXTURES="$BATS_TEST_DIRNAME/fixtures/test-sh"
  export TMPDIR="$BATS_FILE_TMPDIR"
  local s=0
  "$SCRIPT" "$FIXTURES/failing.bats" >"$BATS_FILE_TMPDIR/failing.out" || s=$?
  echo "$s" >"$BATS_FILE_TMPDIR/failing.status"
}

load_failing_run() {
  status=$(cat "$BATS_FILE_TMPDIR/failing.status")
  lines=()
  while IFS= read -r line; do lines+=("$line"); done <"$BATS_FILE_TMPDIR/failing.out"
  output=$(cat "$BATS_FILE_TMPDIR/failing.out")
}

@test "test.sh: a failing test makes it exit with bats' status, named on the last line" {
  load_failing_run
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "status=1" ]
}

@test "test.sh: stdout carries the plan, the failure and its diagnostics, not the passes" {
  load_failing_run
  [ "${lines[0]}" = "1..2" ]
  [[ "$output" == *"not ok 2 fixture: fails"* ]]
  [[ "$output" == *"fixture diagnostic"* ]]
  [[ "$output" != *"ok 1 fixture: passes"* ]]
}

@test "test.sh: the file it names holds the full TAP output" {
  load_failing_run
  tap_line=$(printf '%s\n' "${lines[@]}" | grep '^tap=')
  tap=${tap_line#tap=}
  grep -qE '^ok 1 fixture: passes( #.*)?$' "$tap"
  grep -q '^not ok 2 fixture: fails' "$tap"
}

@test "test.sh: a passing run exits 0 with status=0 last" {
  run "$SCRIPT" "$FIXTURES/passing.bats"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "status=0" ]
  [[ "$output" != *"not ok"* ]]
  [[ "$output" == *"slowest tests:"* ]]
  [[ "$output" == *"ms  passing.bats  fixture: passes"* ]]
  [[ "$output" == *"tests_time="*"s wall="*"s"* ]]
}

@test "test.sh: a skipped test is shown, since status=0 alone would hide it" {
  run "$SCRIPT" "$FIXTURES/skipping.bats"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok 1 fixture: skipped # skip fixture reason"* ]]
  [[ "$output" == *"ms  skipping.bats  fixture: skipped"* ]]
}

@test "test.sh: an error from bats itself reaches stdout, not only the file" {
  run "$SCRIPT" "$FIXTURES/does-not-exist.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does-not-exist.bats"*"does not exist"* ]]
  [[ "$output" != *"slowest tests:"* ]]
  [ "${lines[${#lines[@]}-1]}" = "status=$status" ]
}

@test "test.sh: without GNU parallel it runs without -j rather than running nothing" {
  stub="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub"
  printf '#!/bin/sh\necho "parallel from moreutils"\nexit 1\n' >"$stub/parallel"
  chmod +x "$stub/parallel"
  PATH="$stub:$PATH" run "$SCRIPT" "$FIXTURES/passing.bats"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1..1" ]
}

@test "test.sh: pins the same bats version as CI" {
  ci=$(grep -o 'bats@[0-9.]*' "$BATS_TEST_DIRNAME/../.github/workflows/ci.yml" | sort -u)
  script=$(grep -o 'bats@[0-9.]*' "$SCRIPT" | sort -u)
  [ -n "$ci" ]
  [ "$ci" = "$script" ]
}
