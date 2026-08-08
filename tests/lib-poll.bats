#!/usr/bin/env bats
#
# Tests for the shared polling primitives. Two halves:
#
#   - The curve, exercised as a pure function. `poll_interval_at` takes elapsed
#     seconds and returns an interval, so its shape is checkable without running
#     a watch at all — no stubs, no sleeping, no accumulated tick state.
#   - The awake clock, which needs time to pass and a machine to suspend. Both
#     are faked: `date` and `sleep` are stubbed on PATH so a six-hour suspend
#     costs nothing and lands on an exact second.

LIB="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/lib-poll.sh"

# A clock we control. `sleep N` advances it by N instead of sleeping; if a
# SUSPEND file holds a number, the next sleep also jumps by that much and clears
# it — which is exactly what a laptop lid does to a poll loop.
setup_clock() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export CLOCK="$BATS_TEST_TMPDIR/clock"; echo 0 > "$CLOCK"
  export SUSPEND="$BATS_TEST_TMPDIR/suspend"
  # Epoch seconds come from the file alone, never from the real clock. Mixing the
  # two leaks however long the test itself took into every assertion, which turns
  # exact expectations into flaky ranges. Other date formats (the ISO stamp in a
  # result line) pass through, since nothing asserts on them.
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
  export PATH="$STUB:$PATH"
}

# --- the curve, as a pure function -----------------------------------------

@test "the default curve hits its stated breakpoints" {
  . "$LIB"
  [ "$(poll_interval_at 0)" = 10 ]
  [ "$(poll_interval_at 1800)" = 30 ]
  [ "$(poll_interval_at 5400)" = 60 ]
  [ "$(poll_interval_at 7200)" = 300 ]
}

@test "the curve interpolates between breakpoints" {
  . "$LIB"
  [ "$(poll_interval_at 900)" = 20 ]    # halfway 10 -> 30
  [ "$(poll_interval_at 3600)" = 45 ]   # halfway 30 -> 60
  [ "$(poll_interval_at 6300)" = 180 ]  # halfway 60 -> 300
}

@test "the curve is flat past the last breakpoint" {
  . "$LIB"
  [ "$(poll_interval_at 7201)" = 300 ]
  [ "$(poll_interval_at 86400)" = 300 ]
  [ "$(poll_interval_at 8640000)" = 300 ]
}

@test "the curve never goes backwards" {
  . "$LIB"
  local prev=0 e iv
  for (( e=0; e<=9000; e+=30 )); do
    iv=$(poll_interval_at "$e")
    [ "$iv" -ge "$prev" ] || { echo "interval fell from $prev to $iv at ${e}s"; false; }
    prev=$iv
  done
}

# The two properties that outlive any particular curve shape. These are the
# operator-facing promises; the breakpoint test above is just today's way of
# keeping them.
@test "nobody waits more than a minute inside the first 90 minutes" {
  . "$LIB"
  local t=0 iv
  while [ "$t" -lt 5400 ]; do
    iv=$(poll_interval_at "$t")
    [ "$iv" -le 60 ] || { echo "interval ${iv}s at ${t}s is over a minute"; false; }
    t=$(( t + iv ))
  done
}

@test "nobody ever waits more than five minutes" {
  . "$LIB"
  local e iv
  for e in 0 1800 5400 7200 20000 86400 8640000; do
    iv=$(poll_interval_at "$e")
    [ "$iv" -le 300 ] || { echo "interval ${iv}s at ${e}s is over the cap"; false; }
  done
}

@test "INTERVAL pins the curve flat" {
  export INTERVAL=7; . "$LIB"
  [ "$(poll_interval_at 0)" = 7 ]
  [ "$(poll_interval_at 100000)" = 7 ]
}

@test "POLL_CURVE replaces the default outright" {
  export POLL_CURVE="0:2 100:12"; . "$LIB"
  [ "$(poll_interval_at 0)" = 2 ]
  [ "$(poll_interval_at 50)" = 7 ]
  [ "$(poll_interval_at 100)" = 12 ]
  [ "$(poll_interval_at 999)" = 12 ]
}

# A malformed knob must fail at source time, before the watch prints anything. A
# silent fallback to the default would hide a caller's typo for the whole watch.
@test "a malformed POLL_CURVE fails loudly rather than falling back" {
  run bash -c "export POLL_CURVE='0:10 bogus'; . '$LIB'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"POLL_CURVE"* ]]

  run bash -c "export POLL_CURVE='0:10 900:x'; . '$LIB'"
  [ "$status" -ne 0 ]

  run bash -c "export POLL_CURVE='60:10 900:30'; . '$LIB'"   # must start at 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"offset 0"* ]]

  run bash -c "export POLL_CURVE='0:10 900:30 900:60'; . '$LIB'"   # must strictly increase
  [ "$status" -ne 0 ]

  run bash -c "export POLL_CURVE=''; . '$LIB'"
  [ "$status" -ne 0 ]
}

# --- the awake clock --------------------------------------------------------

@test "awake time accumulates while the machine is open" {
  setup_clock
  run bash -c ". '$LIB'; poll_init; poll_nap; poll_nap; poll_nap; poll_awake"
  [ "$status" -eq 0 ]
  # INTERVAL is unset, so three naps at the 10s floor.
  [ "$output" = 30 ]
}

# The reason this clock exists. A watch that spent the night suspended has not
# been watching, so the window must not have been spent.
@test "a suspend does not consume the window" {
  setup_clock
  echo 100000 > "$SUSPEND"   # ~28h with the lid shut
  run bash -c ". '$LIB'
    poll_init
    poll_nap
    poll_timed_out && echo TIMED_OUT || echo ALIVE
    echo awake=\$(poll_awake)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALIVE"* ]]
  # 10s of the 6h window spent, not 28 hours of it.
  [[ "$output" == *"awake=10"* ]]
}

@test "the window still ends after enough awake time" {
  setup_clock
  run bash -c "export WINDOW=100; . '$LIB'
    poll_init
    while ! poll_timed_out; do poll_nap; done
    echo done awake=\$(poll_awake)"
  [ "$status" -eq 0 ]
  local awake; awake=$(sed -n 's/^done awake=//p' <<<"$output")
  # At the window, not exactly on it: the loop can only notice between naps, so
  # it lands within one interval past. (Here 101 — the curve is already 11s by
  # t=90, since 10 + 20*90/1800 rounds up a second.)
  [ "$awake" -ge 100 ]
  [ "$awake" -lt 130 ]
}

# Waking at the dormant cap would be least responsive exactly when the human has
# come back to the machine.
@test "the curve returns to the floor after a suspend" {
  setup_clock
  # A short curve with the same shape as the real one, so the walk to the cap is
  # ten naps rather than 250. What's under test is the reset, not the default.
  run bash -c "export POLL_CURVE='0:10 100:300'; . '$LIB'
    poll_init
    while [ \"\$(poll_quiet)\" -lt 100 ]; do poll_nap; done
    echo capped=\$(poll_interval)
    echo 100000 > '$SUSPEND'
    poll_nap
    echo after_wake=\$(poll_interval)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"capped=300"* ]]
  [[ "$output" == *"after_wake=10"* ]]
}

@test "an ordinary slow tick is not mistaken for a suspend" {
  setup_clock
  # Overshoot inside the slack: a loaded machine, not a lid.
  echo 5 > "$SUSPEND"
  run bash -c ". '$LIB'; poll_init; poll_nap; poll_awake"
  [ "$status" -eq 0 ]
  [ "$output" = 15 ]   # charged for all 15s, nothing banked as suspend
}

# poll_broken needs BOTH conditions. Ticks alone are not a duration once a
# failure resets the curve to the floor, and seconds alone would call a single
# slow tick a broken watch.
@test "poll_broken needs both the tick count and the elapsed time" {
  setup_clock
  run bash -c "export FAIL_MAX=10 FAIL_MIN_SECONDS=180; . '$LIB'
    poll_init
    poll_broken 9 0  && echo A_YES || echo A_NO      # too few ticks
    poll_broken 10 0 && echo B_YES || echo B_NO      # enough ticks, no time
    sleep 200
    poll_broken 10 0 && echo C_YES || echo C_NO      # both
    poll_broken 9 0  && echo D_YES || echo D_NO      # time, too few ticks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"A_NO"* ]]
  [[ "$output" == *"B_NO"* ]]
  [[ "$output" == *"C_YES"* ]]
  [[ "$output" == *"D_NO"* ]]
}

# The floor is awake time, so a suspend cannot satisfy it either: waking to a
# reconnecting network must not look like three minutes of being broken.
@test "suspended time does not count toward the failure floor" {
  setup_clock
  run bash -c "export FAIL_MAX=3 FAIL_MIN_SECONDS=180; . '$LIB'
    poll_init
    start=\$(poll_awake)
    echo 100000 > '$SUSPEND'
    poll_nap
    poll_broken 5 \$start && echo BROKEN || echo RIDING"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RIDING"* ]]
}

@test "poll_reset returns the curve to the floor without refunding the window" {
  setup_clock
  run bash -c "export WINDOW=100000 POLL_CURVE='0:10 1000:60'; . '$LIB'
    poll_init
    while [ \"\$(poll_quiet)\" -lt 500 ]; do poll_nap; done
    echo before=\$(poll_interval)
    poll_reset
    echo after=\$(poll_interval)
    echo awake=\$(poll_awake) quiet=\$(poll_quiet)"
  [ "$status" -eq 0 ]
  local before after awake quiet
  before=$(sed -n 's/^before=//p' <<<"$output")
  after=$(sed -n 's/^after=//p' <<<"$output")
  awake=$(sed -n 's/^awake=\([0-9]*\).*/\1/p' <<<"$output")
  quiet=$(sed -n 's/.*quiet=//p' <<<"$output")
  [ "$before" -gt 10 ]      # the curve had grown past the floor
  [ "$after" = 10 ]         # ...and the reset put it back
  [ "$quiet" = 0 ]
  # The window runs from poll_init, and a reset must not give any of it back.
  [ "$awake" -ge 500 ]
}
