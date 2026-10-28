# A clock the suite controls. `load clock` in any suite that runs a watch or the
# poll library, then call `setup_clock` before the run: `date +%s` reads an offset
# file, and `sleep N` advances that file by N and returns at once. Other `date`
# formats (the ISO stamp in a result line, a trace's timestamps) pass through to
# the real binary, since nothing asserts on them.
#
# The pair is the unit: the offset file is the only thing that moves this clock,
# so time advances exactly when a `sleep` runs and by what it asked for.
#
# The stubs are exported functions rather than scripts on PATH: a watch calls
# the clock a dozen times a tick, and a script is a fork and an exec of bash on
# every call where a function runs in the caller's process. It reaches every
# bash the test starts through the environment, as a PATH entry would, so a
# child started with `env -i` sees the real clock. The body runs under the
# caller's options: `${1-}` rather than `$1` for `set -u`, `|| true` on each
# `read` for `set -e`, since `read` returns 1 at an unterminated last line, and
# a plain call to the real binary rather than `exec`, which would replace the
# caller.
#
# One copy, shared by `load clock`, for the reason `tests/reap.bash` gives.
#
# A number in the SUSPEND file is a machine asleep with the lid shut: the next
# `sleep` also jumps the clock by that much and clears it, so `poll_awake` can be
# checked against a nap that lasted longer than it asked for.
setup_clock() {
  export CLOCK="$BATS_TEST_TMPDIR/clock" CLOCK_BASE=1700000000; echo 0 > "$CLOCK"
  export SUSPEND="$BATS_TEST_TMPDIR/suspend"; : > "$SUSPEND"
  # shellcheck disable=SC2329  # invoked by the processes the test starts, not here
  date() {
    local off=0; [ ! -f "$CLOCK" ] || read -r off < "$CLOCK" || true
    if [ "${1-}" = "+%s" ]; then echo $(( CLOCK_BASE + off )); else /bin/date "$@"; fi
  }
  # shellcheck disable=SC2329
  sleep() {
    local now jump=0
    if [ -s "$SUSPEND" ]; then read -r jump < "$SUSPEND" || true; : > "$SUSPEND"; fi
    read -r now < "$CLOCK" || true
    echo $(( now + ${1:-0} + jump )) > "$CLOCK"
  }
  export -f date sleep
}
