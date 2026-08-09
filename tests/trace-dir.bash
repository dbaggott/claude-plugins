# Keep a suite's watch traces inside its own tmpdir. `load trace-dir` in any suite
# that spawns a watch, and call `contain_traces` from its `setup()`.
#
# ⚠️ WITHOUT THIS A TEST RUN WRITES INTO THE DEVELOPER'S REAL TRACE DIRECTORY, and it
# is not obvious from any test that it does. Tracing is on by default and
# `_poll_trace_default` resolves `${TMPDIR:-/tmp}/dnbg-watch` — so a suite that sets
# neither `WATCH_LOG` nor `TMPDIR` inherits the developer's, and every watcher it
# spawns files a trace next to the real ones. Measured at 43 files per full `bats
# tests/` run, against a directory whose entire purpose is to be read by hand after a
# watch dies. `ls -t` there is the documented way in, and it shows the last test run.
#
# The 3-day sweep bounds the growth, and test traces exit cleanly so they classify as
# CLEAN rather than polluting the KILLED bucket — this is hygiene, not a broken
# diagnosis. The sharper edge is an interrupted run (a killed `bats`), whose traces
# would have a `SIGNAL=` line or no terminal line at all and would land in exactly the
# bucket an investigation is reading.
#
# SHARED RATHER THAN COPIED, for the same reason `tests/reap.bash` is: the rationale is
# the expensive part, and three copies of it drift. It is a function rather than a
# `setup()` because two of the three suites define their own.
#
# Tests that deliberately exercise the DEFAULT trace path set their own `TMPDIR`
# inline and so override this — which is why it needs no per-test exceptions.
contain_traces() {
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
}
