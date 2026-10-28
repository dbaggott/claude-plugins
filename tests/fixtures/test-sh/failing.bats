#!/usr/bin/env bats
#
# Input for tests/test-sh.bats, which runs it through scripts/dev/test.sh. It
# sits under fixtures/ because `bats tests/` does not recurse, so the real
# suite never runs it.

@test "fixture: passes" {
  true
}

@test "fixture: fails" {
  echo "fixture diagnostic"
  false
}
