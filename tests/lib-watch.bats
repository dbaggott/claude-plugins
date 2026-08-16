#!/usr/bin/env bats
#
# Tests for the watch bookkeeping shared by the watchers. The counters are
# addressed through eval because bash 3.2 has no associative arrays, so the
# cases below pin the two properties that construction can silently lose: a
# source's streak being its own, and a name with a dash reaching the same slot
# every time.

load trace-dir
load reap

setup() {
  contain_traces
  LIB="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts"
  # shellcheck source=/dev/null
  source "$LIB/lib-poll.sh"
  # shellcheck source=/dev/null
  source "$LIB/lib-watch.sh"
  poll_init
  BROKEN=""
  # shellcheck disable=SC2317  # called through watch_fail
  note_broken() { BROKEN="$1"; }
}

@test "a streak short of FAIL_MAX does not report broken" {
  FAIL_MAX=10 FAIL_MIN_SECONDS=0
  local i
  for i in 1 2 3; do watch_fail pr-view note_broken; done
  [ -z "$BROKEN" ]
}

@test "a streak reaching FAIL_MAX reports broken, naming the source" {
  FAIL_MAX=3 FAIL_MIN_SECONDS=0
  local i
  for i in 1 2 3; do watch_fail pr-view note_broken; done
  [ "$BROKEN" = pr-view ]
}

# Two sources failing alternately are two short streaks, not one long one. A
# shared counter would report a broken watch on a pair of blips.
@test "each source keeps its own streak" {
  FAIL_MAX=3 FAIL_MIN_SECONDS=0
  watch_fail pr-view note_broken
  watch_fail inline-comments note_broken
  watch_fail pr-view note_broken
  watch_fail inline-comments note_broken
  [ -z "$BROKEN" ]
}

# The name is mangled into a variable name, so two sources differing only where
# the mangling collapses would share a slot and each other's streak.
@test "a dashed source name addresses one slot consistently" {
  FAIL_MAX=2 FAIL_MIN_SECONDS=0
  watch_fail inline-comments note_broken
  [ -z "$BROKEN" ]
  watch_fail inline-comments note_broken
  [ "$BROKEN" = inline-comments ]
}

@test "a success clears the streak rather than leaving it one short" {
  FAIL_MAX=2 FAIL_MIN_SECONDS=0
  watch_fail pr-view note_broken
  watch_ok pr-view
  watch_fail pr-view note_broken
  [ -z "$BROKEN" ]
}

# A shape failure follows a call that succeeded, so the fetch counter has just
# been reset. Sharing one counter caps the shape streak at one and it can never
# reach FAIL_MAX — the watch then idles out looking healthy.
@test "a shape streak survives the fetch counter being reset" {
  FAIL_MAX=3 FAIL_MIN_SECONDS=0
  local i
  for i in 1 2 3; do
    watch_ok pr-view
    watch_fail_shape pr-view note_broken
  done
  [ "$BROKEN" = pr-view-shape ]
}

# Grading is the point of the split: a network call gets the transient grace, a
# payload that stopped parsing does not.
@test "a shape failure is not given the transient grace" {
  FAIL_MAX=2 FAIL_MIN_SECONDS=99999
  watch_fail_shape pr-view note_broken
  [ -z "$BROKEN" ]
  watch_fail_shape pr-view note_broken
  [ "$BROKEN" = pr-view-shape ]
}

@test "the re-arm line carries the command under its own header" {
  run watch_rearm '"/x/watch-pr.sh" o/r 1 abc 2026-01-01T00:00:00Z bot'
  [ "${lines[0]}" = "── re-arm ──" ]
  [ "${lines[1]}" = '"/x/watch-pr.sh" o/r 1 abc 2026-01-01T00:00:00Z bot' ]
}
