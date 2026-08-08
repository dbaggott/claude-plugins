#!/usr/bin/env bats
#
# Tests for the merge watcher. `gh` is stubbed on PATH and serves whatever JSON
# the test writes to $STATEFILE, so every branch — merged, closed, conflicted,
# blocked, timed out, blind — is reachable without a network or a real PR.
#
# This watcher used to be 51 lines inlined in git-workflow/SKILL.md, where
# shellcheck couldn't see it and nothing could test it. These are the cases that
# were only ever verified by running it against a live PR and hoping.

WATCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/watch-merge.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export STATEFILE="$BATS_TEST_TMPDIR/state"
  export FAIL_GH="$BATS_TEST_TMPDIR/fail_gh"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
[ -f "$FAIL_GH" ] && exit 1
cat "$STATEFILE"
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  pr_state OPEN CLEAN '[]'
}

# state, mergeStateStatus, statusCheckRollup
pr_state() {
  printf '{"state":"%s","mergeStateStatus":"%s","statusCheckRollup":%s,"reviewDecision":"APPROVED"}' \
    "$1" "$2" "$3" > "$STATEFILE"
}

result_of() { sed -n 's/^result=\([A-Z]*\).*/\1/p' <<<"$1"; }

@test "a merged PR reports MERGED with its state line and payload" {
  pr_state MERGED CLEAN '[]'
  INTERVAL=0 WINDOW=60 run "$WATCH" o/r 1
  [ "$status" -eq 0 ]
  [ "$(result_of "$output")" = MERGED ]
  [[ "$output" == *"state=MERGED mergeStateStatus=CLEAN pending_checks=0"* ]]
  # The JSON is the payload the caller diagnoses from — it must survive.
  [[ "$output" == *'"reviewDecision":"APPROVED"'* ]]
}

@test "a PR closed without merging reports CLOSED" {
  pr_state CLOSED CLEAN '[]'
  INTERVAL=0 WINDOW=60 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = CLOSED ]
}

@test "a conflict reports DIRTY" {
  pr_state OPEN DIRTY '[]'
  INTERVAL=0 WINDOW=60 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = DIRTY ]
}

@test "BLOCKED with nothing pending is terminal" {
  pr_state OPEN BLOCKED '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]'
  INTERVAL=0 WINDOW=60 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = BLOCKED ]
  [[ "$output" == *"pending_checks=0"* ]]
}

# The distinction the whole pending-count exists for: auto-merge waiting on a
# running check looks identical to a hard block in mergeStateStatus alone.
@test "BLOCKED with a check still running keeps waiting" {
  pr_state OPEN BLOCKED '[{"name":"ci","status":"IN_PROGRESS"}]'
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = TIMEOUT ]
  [[ "$output" != *"result=BLOCKED"* ]]
  [[ "$output" == *"pending_checks=1"* ]]
}

# The other rollup shape. A StatusContext has .state, not .status, and reading
# only .status would count a pending legacy status as terminal and report a
# false BLOCKED.
@test "a pending StatusContext counts as pending too" {
  pr_state OPEN BLOCKED '[{"context":"legacy","state":"PENDING"}]'
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = TIMEOUT ]
  [[ "$output" == *"pending_checks=1"* ]]
}

# statusCheckRollup is null on a PR with no checks at all, and iterating null is
# a hard jq error — which would blank the count and disable the terminal-BLOCKED
# test for the rest of the window.
@test "a PR with no checks at all does not break the count" {
  pr_state OPEN BLOCKED 'null'
  INTERVAL=0 WINDOW=60 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = BLOCKED ]
  [[ "$output" == *"pending_checks=0"* ]]
}

@test "an open, mergeable PR times out and reports what it last saw" {
  pr_state OPEN CLEAN '[]'
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = TIMEOUT ]
  [[ "$output" == *"state=OPEN mergeStateStatus=CLEAN"* ]]
}

@test "a merge that lands mid-watch is caught" {
  pr_state OPEN CLEAN '[]'
  ( sleep 2; printf '{"state":"MERGED","mergeStateStatus":"CLEAN","statusCheckRollup":[],"reviewDecision":"APPROVED"}' > "$STATEFILE" ) &
  INTERVAL=1 WINDOW=30 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = MERGED ]
}

@test "exactly one result line is printed" {
  pr_state MERGED CLEAN '[]'
  INTERVAL=0 WINDOW=60 run "$WATCH" o/r 1
  [ "$(grep -c '^result=' <<<"$output")" -eq 1 ]
}

# ERROR is not TIMEOUT. TIMEOUT says the PR sat there; ERROR says the watch
# never saw it. Reporting the first when the second is true tells the operator
# a PR is still open on no evidence at all.
@test "a persistently unreachable gh reports ERROR, not TIMEOUT" {
  touch "$FAIL_GH"
  INTERVAL=0 FAIL_MAX=3 WINDOW=60 run "$WATCH" o/r 1
  [ "$status" -eq 0 ]
  [ "$(result_of "$output")" = ERROR ]
  [[ "$output" == *"reason=pr-view"* ]]
  [[ "$output" != *"result=TIMEOUT"* ]]
  # No state line: there is nothing true to say about the PR.
  [[ "$output" != *"state="* ]]
}

@test "the window running out while blind reports ERROR, not a blank TIMEOUT" {
  touch "$FAIL_GH"
  # FAIL_MAX high enough that the window, not the counter, ends the watch.
  INTERVAL=1 FAIL_MAX=999 WINDOW=2 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = ERROR ]
  [[ "$output" != *"state="* ]]
}

# The counter must reset on success, or one flaky call eventually trips ERROR on
# a perfectly healthy watch.
@test "intermittent failures do not trip ERROR" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$CALLS.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS.n"
case $n in
  1|2|4) exit 1 ;;
  *) cat "$STATEFILE" ;;
esac
EOF
  chmod +x "$STUB/gh"
  pr_state OPEN CLEAN '[]'
  INTERVAL=0 FAIL_MAX=3 WINDOW=3 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = TIMEOUT ]
}

@test "a payload that stops parsing reports a shape ERROR" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo '<html>an error page</html>'
EOF
  chmod +x "$STUB/gh"
  INTERVAL=0 FAIL_MAX=3 WINDOW=60 run "$WATCH" o/r 1
  [ "$status" -eq 0 ]
  [ "$(result_of "$output")" = ERROR ]
  [[ "$output" == *"reason=pr-view-shape"* ]]
}

# Well-formed JSON of the wrong shape is the sneaky one: jq succeeds and returns
# empty, so a watch keyed only on jq's exit status would treat a missing state as
# "not merged" forever.
@test "valid JSON missing the state field is a shape error, not a quiet wait" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo '{"unexpected":"payload"}'
EOF
  chmod +x "$STUB/gh"
  INTERVAL=0 FAIL_MAX=3 WINDOW=60 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = ERROR ]
  [[ "$output" == *"reason=pr-view-shape"* ]]
}

@test "a suspended machine does not burn the window" {
  # Same synthetic clock as tests/lib-poll.bats: sleep advances a file, and the
  # SUSPEND jump stands in for a closed lid.
  export CLOCK="$BATS_TEST_TMPDIR/clock"; echo 0 > "$CLOCK"
  export SUSPEND="$BATS_TEST_TMPDIR/suspend"; echo 100000 > "$SUSPEND"
  cat > "$STUB/date" <<'EOF'
#!/usr/bin/env bash
off=$(cat "$CLOCK" 2>/dev/null || echo 0)
if [ "$1" = "+%s" ]; then echo $(( 1700000000 + off )); else exec /bin/date "$@"; fi
EOF
  cat > "$STUB/sleep" <<'EOF'
#!/usr/bin/env bash
jump=0
if [ -s "$SUSPEND" ]; then jump=$(cat "$SUSPEND"); : > "$SUSPEND"; fi
echo $(( $(cat "$CLOCK") + ${1:-0} + jump )) > "$CLOCK"
EOF
  chmod +x "$STUB/date" "$STUB/sleep"

  # The PR merges on the 4th poll — well after the ~28h "suspend". A wall-clock
  # window would have retired at the first wake and reported TIMEOUT on a PR that
  # was about to merge.
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$CALLS.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS.n"
if [ "$n" -ge 4 ]; then
  echo '{"state":"MERGED","mergeStateStatus":"CLEAN","statusCheckRollup":[],"reviewDecision":"APPROVED"}'
else
  cat "$STATEFILE"
fi
EOF
  chmod +x "$STUB/gh"
  WINDOW=3600 run "$WATCH" o/r 1
  [ "$(result_of "$output")" = MERGED ]
}

# A reviewer/author watcher must never be able to merge anything. Cheap to
# assert, and the failure it guards against is unrecoverable.
@test "the merge watcher never mutates the PR" {
  ! grep -qE 'gh (pr )?(merge|close|review|comment|edit)|--merge|-X (POST|PATCH|PUT|DELETE)' "$WATCH"
}
