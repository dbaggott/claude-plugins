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
#
# The directory name must not be one of those tests' own, and `tmp` was: three of
# them build `$BATS_TEST_TMPDIR/tmp` as their `$home`, so pointing containment at the
# same path made their `export TMPDIR=…` a no-op. `tracing is on with no WATCH_LOG set,
# and lands under TMPDIR` then passed with that export deleted — the one assertion it
# exists to make, silently gone. A distinct name is the whole fix; keep it distinct.
#
# ⚠️ CONTAINMENT IS BY ENVIRONMENT INHERITANCE, so anything that strips the environment
# escapes it. A watch invoked under `env -i` (the shape `tests/hooks.bats` uses for
# hooks) sees no `TMPDIR`, falls back to `/tmp/dnbg-watch`, and this function is
# silently doing nothing. Pass `WATCH_LOG` explicitly in that case.
contain_traces() {
  export TMPDIR="$BATS_TEST_TMPDIR/ambient-tmp"
  mkdir -p "$TMPDIR"
}
