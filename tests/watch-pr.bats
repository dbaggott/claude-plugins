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

# Keeps this suite's watch traces out of the developer's real trace directory; see
# tests/trace-dir.bash for what happens without it.
load trace-dir

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
# The pair is the unit — neither stub is useful alone, because the offset file is
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
  contain_traces
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
    printf '{"state":"%s","isDraft":%s,"headRefOid":"%040d","reviews":%s,"comments":[],"statusCheckRollup":%s,"mergeStateStatus":"%s"}' \
      "$(cat "$PRSTATE" 2>/dev/null || echo OPEN)" \
      "$(cat "$DRAFT" 2>/dev/null || echo false)" "$n" \
      "$(cat "$REVIEWS" 2>/dev/null || echo '[]')" \
      "$(cat "$ROLLUP" 2>/dev/null || echo '[]')" \
      "$(cat "$MERGESTATE" 2>/dev/null || echo CLEAN)" ;;
  "issue view")
    [ -f "$FAIL_PRVIEW" ] && exit 1
    printf '{"state":"OPEN","closedByPullRequestsReferences":%s}' "$(cat "$LINKED" 2>/dev/null || echo '[]')" ;;
  "api "*|"api")
    # The two endpoints issue mode and PR mode reach for are told apart by path, so a
    # test can fail one while the other stays healthy — which is the only way to
    # exercise a source going blind underneath a primary poll that still succeeds.
    case "$*" in
      *timeline*)
        [ -f "$FAIL_TIMELINE" ] && exit 1
        # `--slurp` shape: an array OF PAGES, each itself an array of events. The
        # stub emits it because that is what the watcher parses (`.[][]`); a flat
        # array here would let a `.[]` regression pass.
        cat "$XREF" 2>/dev/null || echo '[[]]' ;;
      *)
        [ -f "$FAIL_COMMENTS" ] && exit 1
        echo '[]' ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PRSTATE="$BATS_TEST_TMPDIR/prstate"
  export ROLLUP="$BATS_TEST_TMPDIR/rollup"
  export MERGESTATE="$BATS_TEST_TMPDIR/mergestate"
  export PATH="$STUB:$PATH" CALLS
  export FAIL_PRVIEW="$BATS_TEST_TMPDIR/fail_prview"
  export FAIL_COMMENTS="$BATS_TEST_TMPDIR/fail_comments"
  export FAIL_TIMELINE="$BATS_TEST_TMPDIR/fail_timeline"
  export HEADCOUNT="$BATS_TEST_TMPDIR/headcount"
  export LINKED="$BATS_TEST_TMPDIR/linked"
  export XREF="$BATS_TEST_TMPDIR/xref"
  export REVIEWS="$BATS_TEST_TMPDIR/reviews"
  export DRAFT="$BATS_TEST_TMPDIR/draft"
  export TICKS="$BATS_TEST_TMPDIR/ticks"
}

# One formal review, in the shape `gh pr view --json reviews` returns.
#
# `submittedAt` is deliberately ancient: every test using this arms the watch with a
# `since` far in the future, so the edge-triggered count cannot see it. That is the
# situation being tested — a verdict that landed before the watch existed — and a
# recent timestamp would let the SINCE path pass these tests with the level-triggered
# check removed entirely.
reviews() {  # <state> <commit-sha> <login>
  printf '[{"state":"%s","submittedAt":"1970-01-02T00:00:00Z","author":{"login":"%s"},"commit":{"oid":"%s"}}]' \
    "$1" "$3" "$2"
}

# One cross-referenced PR, on the page given, in the shape `gh api --paginate --slurp`
# returns. `pages 2` puts it on the second page — where a real timeline puts anything
# new, since the endpoint is oldest-first with no way to invert it.
xref_pages() {  # <page-count> <pr-url>
  local n="$1" url="$2" i out=""
  for (( i = 1; i < n; i++ )); do out="$out[],"; done
  printf '[%s[{"event":"cross-referenced","source":{"issue":{"pull_request":{},"html_url":"%s"}}}]]' \
    "$out" "$url"
}

# (a) every poll fails -> exactly one ERROR, and never IDLE.
@test "a source failing FAIL_MAX times reports ERROR, not IDLE" {
  touch "$FAIL_PRVIEW"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
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
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=3 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [[ "$output" != *"result=ERROR"* ]]
  [[ "$output" == *"result=IDLE"* ]]
}

# (c) the insidious one: the primary poll stays healthy, so the watch looks fine
# while thread replies silently never register.
@test "a failing inline-comments query reports ERROR naming that source" {
  touch "$FAIL_COMMENTS"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [[ "$output" == *"result=ERROR"* ]]
  [[ "$output" == *"reason=inline-comments"* ]]
}

# (d) the curve: gaps widen while nothing happens, and collapse on a change.
# POLL_CURVE is the real knob (lib-poll.sh); tests/lib-poll.bats covers its shape
# as a pure function, so what's being checked here is that the watch actually
# drives it — that quiet widens the gap and a change resets it.
@test "the interval grows while quiet and returns to the floor on a change" {
  AT_TICK=4 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=1 \
  POLL_CURVE="0:1 3:4" SETTLE=1 WINDOW=20 \
    run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
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
    run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
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
    run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
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
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=pr-view-shape"* ]]
  [[ "$output" != *"result=IDLE"* ]]
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
  INTERVAL=1 FAIL_MAX=99 FAIL_MIN_SECONDS=0 WINDOW=2 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result="* ]]
}

# issue mode shares the loop; only what it polls differs.
@test "a valueless --exclude is refused as bad-args, not left to die silently" {
  INTERVAL=1 WINDOW=2 run "$WATCH" --exclude --issue o/r 56 "" 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR reason=bad-args"* ]]
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
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 2000-01-01T00:00:00Z bot --role=reviewer
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
  INTERVAL=1 FAIL_MAX=2 FAIL_MIN_SECONDS=0 WINDOW=20 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
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
  INTERVAL=1 SETTLE=1 WINDOW=25 run "$WATCH" o/r 1 "" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=COMMITS"* ]]
  [[ "$output" == *"new_head=$(sha40 9)"* ]]
}

# An empty slug makes `mine` match no login, so the watch wakes on its OWN posts and
# re-reviews itself — the exact loop the argument exists to prevent, and silent.
@test "an empty bot slug is refused on the PR path" {
  INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z "" --role=reviewer
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
  INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 0000000 1970-01-01T00:00:00Z bot --role=reviewer
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
  INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 000000000000000000000000000000000000000A 1970-01-01T00:00:00Z bot --role=reviewer
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
    run "$WATCH" o/r 1 000000000000000000000000000000000000000A 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=bad-args"* ]]
  [[ "$output" != *"result=COMMITS"* ]]
}

# The two values callers legitimately pass must be untouched by the check above: a full
# SHA polls normally, and an empty one still self-heals (covered above) rather than
# being refused.
@test "a full 40-character last_head still polls normally" {
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" != *"bad-args"* ]]
}

# --issue never reads <last_head>, so validating it there would reject arguments no
# caller has any reason to make well-formed.
@test "a verdict posted before the watch was armed still wakes it" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  # `since` is past the review, so the edge-triggered count sees nothing: without the
  # level-triggered check this is IDLE.
  [[ "$output" == *"result=ACTIVITY"* ]]
  # The field the caller re-arms from. Absent, the next arm has no baseline to pass and
  # wakes on this same verdict immediately, forever.
  [[ "$output" == *"verdict_sha=$(sha40 0)"* ]]
}

# The other half of the contract: the caller says it handled that verdict, so the watch
# must not re-wake on it. Without this the flag trades a missed review for a hot loop.
@test "a verdict the caller has already handled does not wake the watch" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot "--last-verdict=$(sha40 0)" --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" != *"result=ACTIVITY"* ]]
}

# Omitting the flag has to leave the watch exactly as it was, or every caller that has
# not been updated changes behaviour on upgrade.
@test "a standing verdict wakes a first arm, which has handled none" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "$output" == *"verdict_sha=$(sha40 0)"* ]]
  [[ "$output" == *"verdict=APPROVED"* ]]
}

# The self-wake the `<bot_slug>` argument exists to prevent, reached through the one
# check that ignores `since` — so unlike every other path it cannot age out of it. The
# reviewer's own approval sits at HEAD for the life of the PR, so an unfiltered check
# wakes it on its own review on the first tick of every arm.
@test "the watch does not wake on its own verdict" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" bot)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" != *"result=ACTIVITY"* ]]
}

# GraphQL reports a Bot author's login as `<slug>`, REST as `<slug>[bot]`. Both forms
# have to be excluded here for the same reason they are excluded everywhere else.
@test "the watch does not wake on its own verdict under the [bot] spelling" {
  printf '%s' "$(reviews CHANGES_REQUESTED "$(sha40 0)" 'bot[bot]')" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
}

# A verdict the author has pushed past is stale by construction — it needs a fresh
# review, and waking on it would fire after every push about feedback already handled.
@test "a verdict left behind by a push does not wake the watch" {
  printf '%s' "$(reviews CHANGES_REQUESTED "$(sha40 5)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" != *"result=ACTIVITY"* ]]
}

# `COMMENTED` is not a verdict: a reviewer answering a thread posts one, so counting it
# would wake on every exchange — and here, on every tick, since this check ignores
# `since`. Same set as pr-verdict.sh, which tests/coupling.bats pins.
@test "a COMMENTED review is not a verdict for the level-triggered check" {
  printf '%s' "$(reviews COMMENTED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=IDLE"* ]]
}

# Same reasoning as `<last_head>`: the value is compared as a string against the
# 40-character `commit.oid` GitHub returns, so an abbreviated one can never match and
# would silently re-wake on a verdict the caller said it handled.
@test "an abbreviated --last-verdict is refused as bad-args" {
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --last-verdict=0000000 --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR reason=bad-args"* ]]
}

# The valueless form, refused for the reason `--exclude` is: only the `=` spelling can
# carry a value, and the bare one would otherwise arm the check with no baseline.
@test "a valueless --last-verdict is refused as bad-args" {
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --last-verdict --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR reason=bad-args"* ]]
}

# Nothing in issue mode reads a verdict — no reviews, no HEAD — so accepting the flag
# there would take an argument whose whole purpose is guaranteeing a wake and guarantee
# nothing, with the same IDLE either way.
@test "trailing flags work in either order" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --was-draft --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=READY"* ]]
  [[ "$output" == *"verdict_sha=$(sha40 0)"* ]]

  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --was-draft --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=READY"* ]]
  [[ "$output" == *"verdict_sha=$(sha40 0)"* ]]
}

# Marking a PR ready is neither a push nor a review nor a comment, so it is invisible
# without `--was-draft` and the PR is picked up on its next push, or never. A burst
# accumulating behind the held-back draft has no release short of this transition.
@test "--was-draft reports a draft being marked ready" {
  printf true > "$DRAFT"
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  AT_TICK=3 AT_TICK_FILE="$DRAFT" AT_TICK_VALUE=false \
  INTERVAL=1 SETTLE=1 WINDOW=20 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --was-draft --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=READY"* ]]
  # The verdict fired on tick 1, was held back with the draft, and rode out on READY
  # rather than being dropped — the caller re-arms from `verdict_sha` either way.
  [[ "$output" == *"verdict_sha=$(sha40 0)"* ]]
}

@test "an unrecognised trailing argument is refused rather than ignored" {
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --no-such-flag --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR reason=bad-args"* ]]
}

# A stray trace has to say WHICH watch died. Without the arguments it names only a
# script and a pid — enough to see that a watch was killed, useless for correlating
# a cohort of kills against the PRs they were watching.
@test "START records the watcher's own arguments" {
  local home="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$home"
  TMPDIR="$home" INTERVAL=1 WINDOW=3 run "$WATCH" o/r 77 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  local f; f=$(find "$home/dnbg-watch" -name 'watch-pr-*.log' | head -1)
  [ -n "$f" ]
  grep -q "args=\[o/r 77 $(sha40 0) 1970-01-01T00:00:00Z bot --role=reviewer\]" "$f"
}

# ...INCLUDING the role, which is what tells two watches on one PR apart. A trace
# is the only evidence a killed watch leaves, and an author watch and a reviewer
# watch on the same number are otherwise the same line.
@test "START records the role, so two watches on one PR are distinguishable" {
  local home="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$home"
  TMPDIR="$home" INTERVAL=1 WINDOW=2 run "$WATCH" o/r 56 "" 1970-01-01T00:00:00Z bot --role=author
  [ "$status" -eq 0 ]
  local f; f=$(find "$home/dnbg-watch" -name 'watch-pr-*.log' | head -1)
  [ -n "$f" ]
  grep -q -- "--role=author" "$f"
}

# The watcher polls the comments it reports on, so reporting only a flag makes the
# caller fetch them again. These pin what it carries with the flag: enough to know
# whether to act and on what, and the call that fetches the rest.

@test "the activity behind activity=1 is summarised, without the body" {
  printf '[{"state":"CHANGES_REQUESTED","submittedAt":"2999-01-01T00:00:00Z","author":{"login":"someone"},"body":"four things below","commit":{"oid":"%s"}}]' \
    "$(sha40 0)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ACTIVITY"* ]]
  [[ "$output" == *'"kind":"review"'* ]]
  [[ "$output" == *'"state":"CHANGES_REQUESTED"'* ]]
  # The body is pr-round.sh's to deliver. Emitting it here made the wake look like
  # a whole round while carrying neither the threads nor the diff one needs.
  [[ "$output" != *"four things below"* ]]
}

# A prose pointer to pr-round.sh in another file loses to any instruction to batch
# reads — it arrives after the work it was meant to direct. The filled-in command
# is reachable from the wake itself, which is what makes it hold.
@test "a reported round prints the pr-round.sh call with its arguments filled in" {
  printf '[{"state":"CHANGES_REQUESTED","submittedAt":"2999-01-01T00:00:00Z","author":{"login":"someone"},"body":"x","commit":{"oid":"%s"}}]' \
    "$(sha40 0)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"── next ──"* ]]
  [[ "$output" == *"/pr-round.sh\" o/r 1 $(sha40 0) 1970-01-01T00:00:00Z bot"* ]]
}

# pr-round.sh takes five arguments and answers bad-args to four, so a blank
# last-head has to reach it as a literal `""` rather than collapsing away.
@test "a blank last-head prints as an empty-string argument, not a missing one" {
  printf '[{"state":"CHANGES_REQUESTED","submittedAt":"2999-01-01T00:00:00Z","author":{"login":"someone"},"body":"x","commit":{"oid":"%s"}}]' \
    "$(sha40 0)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"/pr-round.sh\" o/r 1 \"\" 1970-01-01T00:00:00Z bot"* ]]
}

# The case the flag exists for: a push and a reply in one burst. The reply is only
# ever reported here — the caller re-arms with since_iso set to now, so a payload
# it did not carry is filtered out for good.
@test "a push that lands with replies carries the replies" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")
    n=$(( $(cat "$TICKS" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$TICKS"
    h=0; [ "$n" -ge 2 ] && h=1
    printf '{"state":"OPEN","isDraft":false,"headRefOid":"%040d","reviews":[],"comments":[]}' "$h" ;;
  "api "*|"api")
    echo '[{"created_at":"2999-01-01T00:00:00Z","user":{"login":"someone"},"path":"a.sh","line":7,"id":99,"body":"the fourth thing"}]' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=COMMITS"* ]]
  [[ "$output" == *"activity=1"* ]]
  [[ "$output" == *'"kind":"inline"'* ]]
  # The REST comment id an `in_reply_to` reply takes, which is otherwise a
  # re-fetch. Survives the body being dropped; the GraphQL thread id is a
  # different namespace and comes from the round packet's threads section.
  [[ "$output" == *'"id":99'* ]]
  [[ "$output" != *"the fourth thing"* ]]
}

# A caller reading the lines above `result=` must not find leftovers on a quiet
# watch — an empty burst has to look empty. The re-arm line is not a leftover:
# IDLE is the result a caller always re-arms from, so it is the one that most
# needs the next invocation attached.
@test "a quiet watch carries its re-arm line and no burst content" {
  INTERVAL=1 WINDOW=3 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "$output" == *"── re-arm ──"* ]]
  [[ "$output" != *"── next ──"* ]]
  [[ "$output" != *'"kind":'* ]]
}

@test "a verdict wake names the state that stands, not only its SHA" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=APPROVED"* ]]
  [[ "$output" == *"verdict_sha=$(sha40 0)"* ]]
}

# The branching hint has to name the LAST verdict, or it sends the caller down the
# clean-review path over a standing objection. Same rule pr-verdict.sh is pinned to.
@test "verdict= reports a reversal at the same SHA, not the approval under it" {
  printf '[{"state":"APPROVED","submittedAt":"1970-01-02T00:00:00Z","author":{"login":"someone"},"commit":{"oid":"%s"}},
           {"state":"CHANGES_REQUESTED","submittedAt":"1970-01-02T00:00:00Z","author":{"login":"someone"},"commit":{"oid":"%s"}}]' \
    "$(sha40 0)" "$(sha40 0)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=CHANGES_REQUESTED"* ]]
}

# THE VERDICT READ MUST DIE LOUDLY RATHER THAN EMPTY OUT. Its jq is unguarded on
# purpose — a payload that stops parsing there is a shape change, never transient —
# and feeding the substitution to `read` through a heredoc discards its exit status,
# leaving both variables empty so the level-triggered check silently stops firing and
# the watch reports a quiet PR. `commit` as a number breaks that query alone: the
# shape gate passes, and the activity count above it reads fields that are all there.
@test "a verdict payload that stops parsing kills the watch instead of reporting quiet" {
  printf '[{"submittedAt":"1970-01-02T00:00:00Z","author":{"login":"someone"},"state":"APPROVED","commit":5}]' \
    > "$REVIEWS"
  INTERVAL=1 WINDOW=3 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -ne 0 ]
  [[ "$output" != *"result="* ]]
}

# --- conditions absorbed from watch-merge.sh --------------------------------
#
# These were a second watcher a caller swapped to after a clean review, and the
# swap is what lost every review posted after an approval. They are the author
# role's results now, so one arming covers a PR from open to merge.

@test "a merged PR stops the watch" {
  echo MERGED > "$PRSTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CLOSED state=MERGED" ]]
}

@test "a PR closed without merging stops the watch" {
  echo CLOSED > "$PRSTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CLOSED state=CLOSED" ]]
}

@test "a conflict with base reports DIRTY to the author" {
  echo DIRTY > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=DIRTY* ]]
}

# The reviewer has nothing to do about a conflict with base, so waking them on
# one is noise they cannot act on.
@test "a conflict is not the reviewer's business" {
  echo DIRTY > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=IDLE* ]]
}

@test "a block with nothing pending is terminal and reaches the author" {
  echo BLOCKED > "$MERGESTATE"
  echo '[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=BLOCKED cause=terminal"* ]]
}

# The distinction the old watcher counted pending checks to make, now made in the
# backend: a required check still running is auto-merge waiting, not a block.
@test "a block with a check still running keeps waiting" {
  echo BLOCKED > "$MERGESTATE"
  echo '[{"name":"e2e","status":"IN_PROGRESS","conclusion":""}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
}

# A watcher is read-only. Nothing it does may write to the PR.
@test "the watch never mutates the PR" {
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  ! grep -qE " (pr (merge|close|ready|edit|review|comment)|api .*-X (POST|PATCH|PUT|DELETE))" "$CALLS"
}
