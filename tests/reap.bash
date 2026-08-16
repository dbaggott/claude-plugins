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
  while read -r p; do
    [ -n "$p" ] || continue
    # ⚠️ VERIFY BEFORE KILLING. Recorded pids are routinely already dead by the time
    # this runs — the signal tests kill the watch themselves, and one test records a
    # `( sleep 2 ) &` inside a ~25s test. `kill` on a corpse is a harmless no-op right
    # up until the number is recycled, at which point it kills a stranger, possibly in
    # another session. Reuse needs a full wrap of the pid space and is not plausible at
    # observed churn (~5/sec against a ~23s worst-case window), but the guard costs one
    # `ps` and removes the failure mode rather than relying on that arithmetic holding.
    # `-ww`, not a bare `ps`. procps-ng honours COLUMNS and falls back to 80 with
    # no tty, which is CI — and the substring being matched sits well past column 80
    # in these children (`bash -c export WATCH_LOG=… . '<repo>/…/lib-poll.sh' …`). A
    # truncated line matches nothing, the reaper silently stops reaping, and the
    # spare-a-stranger test below still passes because it asserts an absence. `-ww`
    # is unlimited-width on both BSD and procps.
    case "$(ps -ww -o command= -p "$p" 2>/dev/null)" in
      # Deliberately NOT matching a bare `sleep`: the nap child is reaped by the
      # signal handler, and the one test that backgrounds a `sleep` lets it expire on
      # its own — while `sleep` is common enough that matching it would put most of
      # the recycled-pid risk straight back.
      *watch-pr.sh*|*watch-issue.sh*|*lib-poll.sh*) kill "$p" 2>/dev/null ;;
    esac
  done < "$BATS_TEST_TMPDIR/pids"
  return 0
}
