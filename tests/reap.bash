# Reap anything a test backgrounded. `load reap` in any suite that spawns a watch.
#
# ⚠️ A WATCH LOOP HAS NO EXIT CONDITION — that is the point of it — so a backgrounded
# one is stopped only by the `kill` its test performs. Anything between the spawn and
# that kill (an earlier assertion failing, the suite interrupted, the session dying)
# orphans it to `ppid=1`, where nothing will ever stop it. Two such orphans from an
# earlier branch were found on a developer machine at 5h57m each.
#
# SHARED RATHER THAN COPIED because the convention is now cross-file: a test writes a
# pid to `$BATS_TEST_TMPDIR/pids` and trusts a net to catch it. A copy of the net that
# exists in only one suite is worse than none — the next spawn in the suite without it
# inherits the belief and not the protection.
#
# Suites that spawn a watch must ALSO bound its loop (`for _ in 1 2 3`, not `while :`),
# so an escapee expires on its own rather than outliving the run.
teardown() {
  local p
  [ -f "${BATS_TEST_TMPDIR:-}/pids" ] || return 0
  while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$BATS_TEST_TMPDIR/pids"
  return 0
}
