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

# Reaps anything a test backgrounds; see tests/reap.bash for why it is shared.
load reap

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

# ---------------------------------------------------------------------------
# Tracing (WATCH_LOG). The point of these is the SHAPE of the evidence a dead
# watch leaves, so they assert on what is present AND on what is absent.

@test "tracing off installs no traps, so the default path is unchanged" {
  setup_clock
  # The traps are the only thing tracing adds that alters the exit path, so
  # "none installed" is the real claim — stronger than "no file was written",
  # which would pass simply because nothing named one.
  run bash -c "unset WATCH_LOG; export WINDOW=50 POLL_CURVE='0:10'; . '$LIB'
    poll_init; poll_nap; trap -p TERM EXIT | wc -l"
  [ "$status" -eq 0 ]
  [ "$(tr -d '[:space:]' <<<"$output")" = 0 ]
}

@test "WATCH_LOG records a start, one line per tick, and the exit" {
  setup_clock
  local log="$BATS_TEST_TMPDIR/trace.log"
  run bash -c "export WATCH_LOG='$log' WINDOW=50 POLL_CURVE='0:10'; . '$LIB'
    poll_init; poll_nap; poll_nap"
  [ "$status" -eq 0 ]
  grep -q ' START script=' "$log"
  [ "$(grep -c ' tick interval=' "$log")" = 2 ]
  grep -q ' EXIT code=0' "$log"
}

@test "the exit line carries the status that killed the watch" {
  setup_clock
  local log="$BATS_TEST_TMPDIR/trace.log"
  # A `set -e` death is the case worth pinning: it is indistinguishable from a
  # clean finish in the task output, because both leave the same empty file.
  run bash -c "export WATCH_LOG='$log' WINDOW=50 POLL_CURVE='0:10'; set -e; . '$LIB'
    poll_init; false; echo unreachable"
  [ "$status" -ne 0 ]
  [[ "$output" != *unreachable* ]]
  grep -q 'EXIT code=1' "$log"
}

@test "a signal is logged mid-nap and re-raised with its own status" {
  # Deliberately NOT setup_clock: this one needs a real nap to be interrupted.
  local log="$BATS_TEST_TMPDIR/trace.log"
  # Bounded (`1 2 3`), not `while :`. The teardown above is the real guard, but a
  # loop that cannot outlive three naps means even a leak that escapes it expires on
  # its own rather than becoming another 6-hour orphan.
  bash -c "export WATCH_LOG='$log' WINDOW=600 POLL_CURVE='0:30'; . '$LIB'
    poll_init; for _ in 1 2 3; do poll_nap; done" &
  local pid=$! i=0
  echo "$pid" >> "$BATS_TEST_TMPDIR/pids"
  # Generously bounded: this only waits for the child to install its traps and write
  # START. Too short and a loaded runner lets the `kill` land before any trap exists,
  # failing for a reason unrelated to what is under test. The 3s deadline below is
  # the assertion and stays tight; this one is setup and should not be.
  while [ ! -s "$log" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  [ -s "$log" ] || { echo "child never started tracing"; return 1; }
  kill -TERM "$pid"

  # ⚠️ THE DEADLINE IS THE ASSERTION. The nap is 30s; a foreground `sleep` defers
  # the trap until it finishes, so if poll_nap ever goes back to one, nothing is
  # in the log within three seconds and this fails. That regression is otherwise
  # invisible — the line still appears eventually, just far too late to be true.
  local j=0
  while ! grep -q 'SIGNAL=TERM' "$log" 2>/dev/null && [ "$j" -lt 30 ]; do sleep 0.1; j=$((j + 1)); done
  grep -q 'SIGNAL=TERM' "$log"

  local st=0; wait "$pid" || st=$?
  [ "$st" -eq 143 ]                 # re-raised, so the status still names the signal
  ! grep -q 'EXIT code=' "$log"     # ...and the EXIT trap did not also claim it
}

@test "a zero interval is refused rather than spinning" {
  # `INTERVAL=1` made poll_nap return instantly, turning the watch into a busy loop
  # around `gh` — measured at 200 naps in 2s, which is the hourly REST budget gone
  # inside a minute and the watch then blind behind rate-limit failures, still
  # reporting an ordinary IDLE. Offsets may be 0; intervals may not.
  run bash -c "export INTERVAL=0; . '$LIB'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 1s"* ]]
  # The offset half must still accept 0 — the curve is required to start there.
  run bash -c "export POLL_CURVE='0:10 60:30'; . '$LIB'; poll_interval_at 0"
  [ "$status" -eq 0 ]
  [ "$output" = 10 ]
}

@test "a signalled watch does not leave its sleep behind" {
  local log="$BATS_TEST_TMPDIR/trace.log"
  bash -c "export WATCH_LOG='$log' WINDOW=600 POLL_CURVE='0:30'; . '$LIB'
    poll_init; for _ in 1 2 3; do poll_nap; done" &
  local pid=$! i=0
  echo "$pid" >> "$BATS_TEST_TMPDIR/pids"
  while [ ! -s "$log" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  # The sleep is the child of the watch; find it before the watch dies.
  local nap; nap=$(pgrep -P "$pid" 2>/dev/null | head -1)
  [ -n "$nap" ] || skip "could not observe the nap child on this platform"
  kill -TERM "$pid"; wait "$pid" 2>/dev/null || true
  # Re-raising kills the shell; without the reap the sleep outlives it by up to a
  # full interval — 300s at the cap.
  local j=0
  while kill -0 "$nap" 2>/dev/null && [ "$j" -lt 30 ]; do sleep 0.1; j=$((j + 1)); done
  ! kill -0 "$nap" 2>/dev/null
}

@test "a SIGKILL leaves a heartbeat and neither a signal nor an exit line" {
  # ⚠️ ROW THREE OF THE TABLE, and the only outcome that is an ABSENCE. The whole
  # design rests on "heartbeat, but no SIGNAL and no EXIT" meaning an uncatchable
  # kill, so it is the row most exposed to silent regression: anything that later
  # buffers the tick line, or adds a trap catching what should be uncatchable, turns
  # a real SIGKILL into "the watch was never running" with every other test green.
  local log="$BATS_TEST_TMPDIR/trace.log"
  bash -c "export WATCH_LOG='$log' WINDOW=600 POLL_CURVE='0:30'; . '$LIB'
    poll_init; for _ in 1 2 3; do poll_nap; done" &
  local pid=$! i=0
  echo "$pid" >> "$BATS_TEST_TMPDIR/pids"
  while [ ! -s "$log" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  [ -s "$log" ] || { echo "child never started tracing"; return 1; }

  kill -KILL "$pid"
  local st=0; wait "$pid" 2>/dev/null || st=$?
  [ "$st" -eq 137 ]                        # uncatchable, so the status says so
  grep -q ' tick interval=' "$log"         # ...the heartbeat is what dates the death
  ! grep -q 'SIGNAL=' "$log"               # ...and neither handler can have run
  ! grep -q 'EXIT code=' "$log"
}

@test "an unwritable WATCH_LOG fails loudly instead of tracing nothing" {
  # A path under a directory that does not exist wrote nothing at all — not even
  # START — which reads as row three: killed before its first tick. The most
  # misleading outcome the feature has, from the likeliest operator typo.
  run bash -c "export WATCH_LOG='$BATS_TEST_TMPDIR/nope/watch.log'; . '$LIB'; poll_init"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not writable"* ]]
}

@test "a reap of an already-dead nap child does not abort the handler" {
  # The race the reap opened: `wait` reaps the nap child a moment before
  # `_poll_napper` is cleared, so a signal arriving in that window finds a pid that
  # is already gone. Under `set -e` the failing `kill` aborted the handler before
  # the re-raise, and the death was recorded as an ordinary exit — a SIGNAL line and
  # an EXIT line together, which the header table says cannot happen.
  local log="$BATS_TEST_TMPDIR/trace.log"
  run bash -c "set -euo pipefail; export WATCH_LOG='$log'; . '$LIB'
    poll_init
    _poll_napper=999999   # certainly gone
    kill -TERM \$\$
    sleep 5"
  [ "$status" -eq 143 ]              # re-raised, so the status still names the signal
  grep -q 'SIGNAL=TERM' "$log"
  ! grep -q 'EXIT code=' "$log"      # ...and the handler did not fall through to EXIT
}
