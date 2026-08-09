#!/usr/bin/env bats
#
# Tests for the shared PR/issue watcher. `gh` is stubbed on PATH, so these
# exercise the loop's own logic — failure counting, the backoff curve, and how
# the two interact — without touching the network.
#
# The clock is stubbed too (see `setup_clock`), so no test in this file sleeps for
# real: every WINDOW, INTERVAL and SETTLE below is in synthetic seconds. That also
# makes the timing assertions exact rather than tolerant.

WATCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/watch-pr.sh"

# Reaps anything a test backgrounds; see tests/reap.bash for why it is shared. No test
# here backgrounds anything any more — mid-watch changes are scheduled by tick count
# now that the clock is stubbed — so this is currently a no-op, kept as the net for the
# next spawn rather than removed. reap.bash's own note is the reason: a net that exists
# in only some suites is worse than none, because the next spawn inherits the belief
# and not the protection.
load reap

# `<last_head>` must be a full 40-character lowercase SHA, so tests need one that
# reads as a version number. Digits are hex, so `%040d` is both.
#
# ⚠️ KEEP THIS IN STEP WITH THE `headRefOid` THE `gh` STUB PRINTS. The watch compares
# the argument against the observed head as strings; if the two formats drift apart,
# every test in the file starts on tick 1 with a spurious COMMITS.
sha40() { printf '%040d' "$1"; }

# A clock the suite controls: `date +%s` reads an offset file, and `sleep N` advances
# that file by N and returns at once.
#
# ⚠️ THE PAIR IS THE UNIT — neither stub is useful alone, because the offset file is
# the only thing that moves this clock. Stub `date` alone and time never advances at
# all; stub `sleep` alone and the naps are still real while `poll_awake` barely moves.
# Either way no WINDOW ever expires and every test that ends in IDLE hangs.
#
# Other `date` formats (the ISO stamp in a result line, the trace's timestamps) pass
# through to the real binary, since nothing here asserts on them.
setup_clock() {
  export CLOCK="$BATS_TEST_TMPDIR/clock"; echo 0 > "$CLOCK"
  cat > "$STUB/date" <<'EOF'
#!/usr/bin/env bash
off=$(cat "$CLOCK" 2>/dev/null || echo 0)
if [ "$1" = "+%s" ]; then echo $(( 1700000000 + off )); else exec /bin/date "$@"; fi
EOF
  cat > "$STUB/sleep" <<'EOF'
#!/usr/bin/env bash
echo $(( $(cat "$CLOCK") + ${1:-0} )) > "$CLOCK"
EOF
  chmod +x "$STUB/date" "$STUB/sleep"
}

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  setup_clock
  # MODE_* files control the stub: presence means "this source fails".
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "$(date +%s) $*" >> "$CALLS"
# One poll is one `pr view`/`issue view`, so that is what counts as a tick — and the
# stub is the only thing in the test that sees one. Anything a test wants to happen
# "later in the watch" is scheduled by tick count rather than by backgrounding a
# `sleep`: with the clock stubbed there is no real time for a background job to wait
# in, and its `sleep` would corrupt the shared clock file besides.
if [ "$2" = view ]; then
  t=$(( $(cat "$TICKS" 2>/dev/null || echo 0) + 1 )); echo "$t" > "$TICKS"
  if [ -n "${AT_TICK:-}" ] && [ "$t" -ge "$AT_TICK" ]; then
    printf '%s' "${AT_TICK_VALUE:-}" > "$AT_TICK_FILE"
  fi
fi
case "$1 $2" in
  "pr view")
    [ -f "$FAIL_PRVIEW" ] && exit 1
    n=$(cat "$HEADCOUNT" 2>/dev/null || echo 0)
    printf '{"state":"OPEN","isDraft":false,"headRefOid":"%040d","reviews":[],"comments":[]}' "$n" ;;
  "issue view")
    [ -f "$FAIL_PRVIEW" ] && exit 1
    printf '{"state":"OPEN","closedByPullRequestsReferences":%s}' "$(cat "$LINKED" 2>/dev/null || echo '[]')" ;;
  "api "*|"api")
    [ -f "$FAIL_COMMENTS" ] && exit 1
    echo '[]' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH" CALLS
  export FAIL_PRVIEW="$BATS_TEST_TMPDIR/fail_prview"
  export FAIL_COMMENTS="$BATS_TEST_TMPDIR/fail_comments"
  export HEADCOUNT="$BATS_TEST_TMPDIR/headcount"
  export LINKED="$BATS_TEST_TMPDIR/linked"
  export TICKS="$BATS_TEST_TMPDIR/ticks"
}

# (a) every poll fails -> exactly one ERROR, and never IDLE.
@test "a source failing FAIL_MAX times reports ERROR, not IDLE" {
  touch "$FAIL_PRVIEW"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [ "$(grep -c '^result=ERROR' <<<"$output")" -eq 1 ]
  [[ "$output" == *"reason=pr-view"* ]]
  [[ "$output" != *"result=IDLE"* ]]
}

# (b) the counter must reset on success, or a flaky link trips a false ERROR.
@test "intermittent failures do not trip ERROR" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$CALLS.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS.n"
case "$1 $2" in
  "pr view") [ "$n" -le 2 ] && exit 1
             echo '{"state":"OPEN","isDraft":false,"headRefOid":"0000000000000000000000000000000000000000","reviews":[],"comments":[]}' ;;
  *) echo '[]' ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=3 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [[ "$output" != *"result=ERROR"* ]]
  [[ "$output" == *"result=IDLE"* ]]
}

# (c) the insidious one: the primary poll stays healthy, so the watch looks fine
# while thread replies silently never register.
@test "a failing comments query reports ERROR naming that source" {
  touch "$FAIL_COMMENTS"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [[ "$output" == *"result=ERROR"* ]]
  [[ "$output" == *"reason=comments"* ]]
}

# (d) the curve: gaps widen while nothing happens, and collapse on a change.
# POLL_CURVE is the real knob (lib-poll.sh); tests/lib-poll.bats covers its shape
# as a pure function, so what's being checked here is that the watch actually
# drives it — that quiet widens the gap and a change resets it.
@test "the interval grows while quiet and returns to the floor on a change" {
  AT_TICK=4 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=1 \
  POLL_CURVE="0:1 3:4" SETTLE=1 WINDOW=20 \
    run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [[ "$output" == *"result=COMMITS"* ]]
  # Gaps between successive polls: must reach >1s while quiet (grown past the
  # floor), and the last gap must be back at the floor after the change.
  mapfile -t ts < <(awk '/pr view/{print $1}' "$CALLS")
  local grew=0 i
  for (( i=1; i<${#ts[@]}; i++ )); do
    [ $(( ts[i] - ts[i-1] )) -gt 1 ] && grew=1
  done
  [ "$grew" -eq 1 ]
  [ $(( ts[${#ts[@]}-1] - ts[${#ts[@]}-2] )) -le 2 ]
}

# (e) the regression the two fixes create together: with ticks elastic, a
# FAIL_MAX counted in ticks would take FAIL_MAX x cap to trip unless the
# interval also resets on failure.
@test "ERROR still trips at floor speed after the ramp reached the cap" {
  start=$(date +%s)
  # The 4th poll arrives with the ramp already at its 8s cap, and is the first to
  # fail — so what follows measures the failure path's own pace, not the ramp's.
  AT_TICK=4 AT_TICK_FILE="$FAIL_PRVIEW" AT_TICK_VALUE=x \
  POLL_CURVE="0:1 2:8" FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 \
    run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  elapsed=$(( $(date +%s) - start ))
  [[ "$output" == *"result=ERROR"* ]]
  # 3 failures at the 1s floor is ~3s after the failures start (~13s in). Without
  # reset-on-failure it would be 3 x the 8s cap on top of that.
  [ "$elapsed" -lt 20 ]
}

# The least obvious invariant in the new code, and the one a refactor is most
# likely to invert: an observed burst outranks ERROR. Reporting ERROR instead
# would drop real activity the caller can never recover, because it re-arms with
# `since` set to now.
@test "a burst in hand outranks ERROR" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") echo '{"state":"OPEN","isDraft":false,"headRefOid":"0000000000000000000000000000000000000009","reviews":[],"comments":[]}' ;;
  *) exit 1 ;;   # comments query always fails
esac
EOF
  chmod +x "$STUB/gh"
  # The head differs from the armed LAST_HEAD, so a burst starts on tick 1.
  # SETTLE is long enough that it cannot settle on its own before FAIL_MAX trips.
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 SETTLE=120 SETTLE_MAX=120 WINDOW=60 \
    run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [[ "$output" == *"result=COMMITS"* ]]
  [[ "$output" != *"result=ERROR"* ]]
}

# The shape paths, at FAIL_MAX > 1. At FAIL_MAX=1 both of these pass while the
# defect is fully present: the successful poll resets the poll counter every
# iteration, so a shape failure sharing it can never exceed 1. That is why the
# threshold matters more than the assertion here.
@test "a persistent payload-shape break reports ERROR, not IDLE" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") echo 'not json at all' ;;
  *) echo '[]' ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=pr-view-shape"* ]]
  [[ "$output" != *"result=IDLE"* ]]
}

@test "a persistent shape break in --issue mode reports ERROR" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue view") echo '<html>an error page</html>' ;;
  *) echo '[]' ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" --issue o/r 56 "" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=issue-view-shape"* ]]
}

@test "malformed JSON never kills the watch without a result line" {
  # Unguarded, the payload parse dies under `set -e`: exit 5, no result= at all.
  # The reviewer skill handles a missing line, but a watch that vanishes is the
  # blindness this whole change removes, wearing a louder costume.
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") echo 'not json at all' ;;
  *) echo '[]' ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 FAIL_MAX=99 FAIL_MIN_SECONDS=0 WINDOW=2 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result="* ]]
}

# issue mode shares the loop; only what it polls differs.
@test "--issue wakes when a linked PR appears" {
  AT_TICK=3 AT_TICK_FILE="$LINKED" AT_TICK_VALUE='[{"number":9}]' \
  INTERVAL=1 WINDOW=20 run "$WATCH" --issue o/r 56 "" 1970-01-01T00:00:00Z bot
  [[ "$output" == *"result=ACTIVITY"* ]]
  grep -q 'issue view' "$CALLS"
}

@test "--issue reports ERROR when it cannot poll at all" {
  touch "$FAIL_PRVIEW"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" --issue o/r 56 "" 1970-01-01T00:00:00Z bot
  [[ "$output" == *"reason=issue-view"* ]]
}

# A reply behind a page of older comments. The endpoint defaults to OLDEST FIRST, so
# without asking for newest-first the watch sees only history, never registers the
# reply, and idles out looking healthy.
@test "a reply behind a page of older comments still registers" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") echo '{"state":"OPEN","isDraft":false,"headRefOid":"0000000000000000000000000000000000000000","reviews":[],"comments":[]}' ;;
  "api "*|"api")
    case "$*" in
      # Newest-first: the reply is on the only page fetched.
      *direction=desc*) echo '[{"created_at":"2999-01-01T00:00:00Z","user":{"login":"someone"}}]' ;;
      # The API default buries it behind history the watch has already seen.
      *)                echo '[{"created_at":"1970-01-01T00:00:00Z","user":{"login":"someone"}}]' ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 2000-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  # Drop direction=desc and this is result=IDLE with a real reply unseen.
  [[ "$output" == *"result=ACTIVITY"* ]]
}

# A payload that parses but has lost `.state` — an API error body is the live case.
# `// empty` alone passed it, leaving STATE="" to match neither MERGED nor CLOSED, so
# the watch ran its whole window against an error and reported IDLE on a closed PR.
@test "a payload missing state is a shape error, not a quiet wait" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") echo '{"message":"Not Found"}' ;;
  *) echo '[]' ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 FAIL_MAX=2 FAIL_MIN_SECONDS=0 WINDOW=20 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR"* ]]
  [[ "$output" == *"pr-view-shape"* ]]
  [[ "$output" != *"result=IDLE"* ]]
}

# An empty <last_head> used to close the commit branch for the life of the watch:
# obs_head gates it and is assigned only inside it, so a push went undetected and the
# watch reported IDLE on a PR that had moved. It now adopts the first HEAD it sees.
@test "an empty last_head self-heals instead of going blind to pushes" {
  echo 0 > "$HEADCOUNT"
  AT_TICK=3 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=9 \
  INTERVAL=1 SETTLE=1 WINDOW=25 run "$WATCH" o/r 1 "" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=COMMITS"* ]]
  [[ "$output" == *"new_head=$(sha40 9)"* ]]
}

# An empty slug makes `mine` match no login, so the watch wakes on its OWN posts and
# re-reviews itself — the exact loop the argument exists to prevent, and silent.
@test "an empty bot slug is refused on the PR path" {
  INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z ""
  # A result line, not a silent non-zero exit: callers read a MISSING result as
  # "killed", which is the one diagnosis this script must not fake.
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR"* ]]
  [[ "$output" == *"reason=bad-args"* ]]
}

# An abbreviated <last_head> can never equal the 40-character headRefOid it is compared
# against, so the watch reported a push on its first tick — observed live, twice, from
# 7-character SHAs. A false COMMITS sends `reviewer` to re-review a range that does not
# exist and tells `git-workflow` the author pushed.
@test "an abbreviated last_head is refused rather than read as a push" {
  INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 0000000 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR"* ]]
  [[ "$output" == *"reason=bad-args"* ]]
  # The failure being fixed: the head the stub serves abbreviates to this argument.
  [[ "$output" != *"result=COMMITS"* ]]
}

# Uppercase is the tempting thing to accept and the one that must not be: GitHub
# returns lowercase, so an uppercase SHA of the right length passes a case-insensitive
# check and then mismatches on every tick — the same false COMMITS, harder to spot.
@test "an uppercase last_head is refused" {
  INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 000000000000000000000000000000000000000A 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=bad-args"* ]]
}

# ⚠️ THE TEST ABOVE PASSES ON A BASH WHERE THE CHECK IS BROKEN, which is why this one
# exists. Bracket ranges match in COLLATION order, and bash 3.2 — stock macOS, and what
# `env bash` finds without a Homebrew bash — interleaves case in a UTF-8 locale, so
# `[!0-9a-f]` spans `a A b B … f F` and never matches `A`. The uppercase rejection is
# then silently a no-op and the false COMMITS is back. CI's bash 5.x has
# `globasciiranges` on and would never show it.
#
# `BASH_ENV` + `shopt -u globasciiranges` reproduces 3.2's matching on a modern bash,
# so the guard is checked on every platform rather than only where the bug is native.
# The locale is load-bearing too: C/POSIX collates by codepoint, under which even the
# range form rejects `A` and this would pass against the defect.
@test "the hex class does not depend on locale collation" {
  locale -a 2>/dev/null | grep -qix 'en_US.utf-*8' \
    || skip "no case-interleaving locale on this machine"
  local envf="$BATS_TEST_TMPDIR/asciiranges-off"
  echo 'shopt -u globasciiranges 2>/dev/null || true' > "$envf"
  BASH_ENV="$envf" LC_ALL=en_US.UTF-8 INTERVAL=1 WINDOW=5 \
    run "$WATCH" o/r 1 000000000000000000000000000000000000000A 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=bad-args"* ]]
  [[ "$output" != *"result=COMMITS"* ]]
}

# The two values callers legitimately pass must be untouched by the check above: a full
# SHA polls normally, and an empty one still self-heals (covered above) rather than
# being refused.
@test "a full 40-character last_head still polls normally" {
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" != *"bad-args"* ]]
}

# --issue never reads <last_head>, so validating it there would reject arguments no
# caller has any reason to make well-formed.
@test "--issue mode is unaffected by the last_head check" {
  INTERVAL=1 WINDOW=2 run "$WATCH" --issue o/r 56 0000000 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" != *"bad-args"* ]]
}

# A stray trace has to say WHICH watch died. Without the arguments it names only a
# script and a pid — enough to see that a watch was killed, useless for correlating
# a cohort of kills against the PRs they were watching.
@test "START records the watcher's own arguments" {
  local home="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$home"
  TMPDIR="$home" INTERVAL=1 WINDOW=3 run "$WATCH" o/r 77 "$(sha40 0)" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  local f; f=$(find "$home/dnbg-watch" -name 'watch-pr-*.log' | head -1)
  [ -n "$f" ]
  grep -q "args=\[o/r 77 $(sha40 0) 1970-01-01T00:00:00Z bot\]" "$f"
}
