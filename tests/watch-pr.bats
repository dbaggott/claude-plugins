#!/usr/bin/env bats
#
# Tests for the shared PR/issue watcher. `gh` is stubbed on PATH, so these
# exercise the loop's own logic — failure counting, the backoff curve, and how
# the two interact — without touching the network.
#
# The clock is stubbed too (see tests/clock.bash), so no test in this file sleeps for
# real: every WINDOW, INTERVAL and SETTLE below is in synthetic seconds. That also
# makes the timing assertions exact rather than tolerant.

WATCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/watch-pr.sh"

# Keeps this suite's watch traces out of the developer's real trace directory; see
# tests/trace-dir.bash for what happens without it.
load trace-dir
load clock

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

setup() {
  contain_traces
  # An author watch asks the role resolver for its login, so no role setup of the
  # developer's may reach it.
  local v; for v in $(compgen -v DNBG_); do unset "$v"; done
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg"
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  setup_clock
  # MODE_* files control the stub: presence means "this source fails".
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
or_default() { local v=$2; [ -f "$1" ] && IFS= read -r -d '' v < "$1"; printf '%s' "$v"; }
read -r off < "$CLOCK"; echo "$(( CLOCK_BASE + off )) $*" >> "$CALLS"
# One poll is one `pr view`, so that is what counts as a tick — and the
# stub is the only thing in the test that sees one. Anything a test wants to happen
# "later in the watch" is scheduled by tick count rather than by backgrounding a
# `sleep`: with the clock stubbed there is no real time for a background job to wait
# in, and its `sleep` would corrupt the shared clock file besides.
if [ "$2" = view ]; then
  t=0; [ -f "$TICKS" ] && read -r t < "$TICKS"; t=$((t + 1)); echo "$t" > "$TICKS"
  if [ -n "${AT_TICK:-}" ] && [ "$t" -ge "$AT_TICK" ]; then
    printf '%s' "${AT_TICK_VALUE:-}" > "$AT_TICK_FILE"
  fi
fi
case "$*" in
  "api user"*) echo operator; exit 0 ;;
  *"/actions/jobs/"*"/logs") [ -f "$RUNLOG" ] || exit 1; cat "$RUNLOG"; exit 0 ;;
esac
case "$1 $2" in
  "pr view")
    [ -f "$FAIL_PRVIEW" ] && exit 1
    n=0; [ -f "$HEADCOUNT" ] && read -r n < "$HEADCOUNT"
    printf '{"state":"%s","isDraft":%s,"headRefOid":"%040d","reviews":%s,"comments":%s,"statusCheckRollup":%s,"mergeStateStatus":"%s","reviewDecision":"%s"}' \
      "$(or_default "$PRSTATE" OPEN)" \
      "$(or_default "$DRAFT_FILE" false)" "$n" \
      "$(or_default "$REVIEWS" '[]')" \
      "$(or_default "$COMMENTS" '[]')" \
      "$(or_default "$ROLLUP" '[]')" \
      "$(or_default "$MERGESTATE" CLEAN)" \
      "$(or_default "$REVIEWDECISION" '')" ;;
  "api "*|"api")
    # Inline comments: the one endpoint the PR fetch reaches beyond `pr view`, so
    # failing it alone is how a source going blind underneath a healthy primary
    # poll gets exercised.
    [ -f "$FAIL_COMMENTS" ] && exit 1
    echo '[]' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export RUNLOG="$BATS_TEST_TMPDIR/runlog"
  export PRSTATE="$BATS_TEST_TMPDIR/prstate"
  export ROLLUP="$BATS_TEST_TMPDIR/rollup"
  export MERGESTATE="$BATS_TEST_TMPDIR/mergestate"
  export REVIEWDECISION="$BATS_TEST_TMPDIR/reviewdecision"
  export PATH="$STUB:$PATH" CALLS
  export FAIL_PRVIEW="$BATS_TEST_TMPDIR/fail_prview"
  export FAIL_COMMENTS="$BATS_TEST_TMPDIR/fail_comments"
  export HEADCOUNT="$BATS_TEST_TMPDIR/headcount"
  export REVIEWS="$BATS_TEST_TMPDIR/reviews"
  export COMMENTS="$BATS_TEST_TMPDIR/comments"
  # NOT `DRAFT`: watch-pr.sh assigns its own `DRAFT` from the payload, and an
  # assignment to an already-exported name keeps the export — so the stub, a
  # grandchild of the watch, would receive `DRAFT=true` in place of this path, find
  # no such file, and report every tick after the first as not-a-draft.
  export DRAFT_FILE="$BATS_TEST_TMPDIR/draft"
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
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
n=0; [ -f "$CALLS.n" ] && read -r n < "$CALLS.n"; n=$((n + 1)); echo "$n" > "$CALLS.n"
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

# Every watcher inherits the heartbeat from the library; this pins that the PR
# watch's own stdout carries it ahead of the result, unparsed by anything.
@test "a wait longer than one heartbeat prints a liveness line before the result" {
  HEARTBEAT=2 INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "alive at="* ]]
  [[ "${lines[-1]}" == result=IDLE* ]]
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
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
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
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
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
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
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

# An unrecognised flag is refused rather than ignored. Ignoring it means a caller
# that misspells `--was-draft` or `--last-checks` gets a watch quietly running
# without that argument's behaviour, and no way to tell from the output.
@test "an unrecognised flag is refused as bad-args, not silently ignored" {
  INTERVAL=1 WINDOW=2 run "$WATCH" o/r 56 "$(sha40 0)" 1970-01-01T00:00:00Z bot \
    --role=reviewer --last-checkz=ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=ERROR reason=bad-args"* ]]
}

# A reply behind a page of older comments. The endpoint defaults to OLDEST FIRST, so
# without asking for newest-first the watch sees only history, never registers the
# reply, and idles out looking healthy.
@test "a reply behind a page of older comments still registers" {
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
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
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
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
  printf true > "$DRAFT_FILE"
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  AT_TICK=3 AT_TICK_FILE="$DRAFT_FILE" AT_TICK_VALUE=false \
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

# The wake carries the round itself, so the caller's first turn reads it rather
# than spending a turn on the fetch.
review_burst() {
  printf '[{"state":"CHANGES_REQUESTED","submittedAt":"2999-01-01T00:00:00Z","author":{"login":"someone"},"body":"x","commit":{"oid":"%s"}}]' \
    "$(sha40 0)" > "$REVIEWS"
}

# The path on the burst's `── round ──` line.
round_file() { sed -n 's/^── round ── //p' <<<"$output"; }

# A copy of the scripts with pr-round.sh replaced by the script on stdin, so a
# test can make the round fetch fail or record that it ran. The watch runs
# pr-round.sh from its own directory.
fake_round() {
  SCRIPTS="$BATS_TEST_TMPDIR/scripts"
  cp -R "$(dirname "$WATCH")" "$SCRIPTS"
  { echo "#!$BASH"; cat; } > "$SCRIPTS/pr-round.sh"
  chmod +x "$SCRIPTS/pr-round.sh"
  export ROUND_CALLS="$BATS_TEST_TMPDIR/round-calls"
}

@test "a reported round's file holds what the pr-round.sh call returns" {
  review_burst
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "$output" != *"── next ──"* ]]
  local f; f=$(round_file)
  [ -s "$f" ]
  [[ "$f" == "$TMPDIR"/pr-round-1-* ]]
  local want
  want=$("$(dirname "$WATCH")/pr-round.sh" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot)
  [ "$(cat "$f")" = "$want" ]
}

# pr-round.sh takes five arguments and answers bad-args to four, so a blank
# last-head has to reach it as an empty argument rather than collapsing away.
@test "a blank last-head reaches the round fetch as an empty argument" {
  review_burst
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  local f; f=$(round_file)
  grep -q '^result=OK' "$f"
}

@test "a round fetch that fails prints the pr-round.sh call instead" {
  fake_round <<'STUB'
echo partial
exit 1
STUB
  review_burst
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$SCRIPTS/watch-pr.sh" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "$output" != *"── round ──"* ]]
  [[ "$output" == *"── next ──"* ]]
  [[ "$output" == *"/pr-round.sh\" o/r 1 $(sha40 0) 1970-01-01T00:00:00Z bot"* ]]
  [[ "$output" == *"watch-pr.sh: the round fetch failed"* ]]
}

@test "a round fetch that writes nothing prints the pr-round.sh call instead" {
  fake_round <<'STUB'
exit 0
STUB
  review_burst
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$SCRIPTS/watch-pr.sh" o/r 1 "" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" != *"── round ──"* ]]
  # The fallback call keeps a blank last-head as a literal `""`, which pr-round.sh
  # needs to count five arguments.
  [[ "$output" == *"/pr-round.sh\" o/r 1 \"\" 1970-01-01T00:00:00Z bot"* ]]
  [ -z "$(find "$TMPDIR" -name 'pr-round-*')" ]
}

# pr-round.sh answers in its last line, so a file ending on anything else, an
# ERROR included, is not a round to read.
@test "a round fetch that ends on result=ERROR prints the pr-round.sh call instead" {
  fake_round <<'STUB'
echo result=ERROR reason=bad-args
STUB
  review_burst
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$SCRIPTS/watch-pr.sh" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" != *"── round ──"* ]]
  [[ "$output" == *"── next ──"* ]]
}

# The same burst, reported because GitHub reads keep failing: a fetch then would
# fail too, so the caller is handed the call to make once GitHub answers.
@test "a burst reported over failing reads does not fetch the round" {
  fake_round <<'STUB'
echo ran >> "$ROUND_CALLS"
echo result=OK
STUB
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'STUB'
case "$1 $2" in
  "pr view") echo '{"state":"OPEN","isDraft":false,"headRefOid":"0000000000000000000000000000000000000009","reviews":[],"comments":[]}' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$STUB/gh"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 SETTLE=120 SETTLE_MAX=120 WINDOW=60 \
    run "$SCRIPTS/watch-pr.sh" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=COMMITS* ]]
  [[ "$output" == *"── next ──"* ]]
  [[ "$output" != *"── round ──"* ]]
  [ ! -e "$ROUND_CALLS" ]
}

# The caller reads the path and re-arms from the line in later Bash calls, whose
# working directory need not be this one.
@test "a relative --round-dir is made absolute, and a missing one is created" {
  review_burst
  cd "$BATS_TEST_TMPDIR"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer \
    --round-dir=new/drafts
  [ "$status" -eq 0 ]
  local f; f=$(round_file)
  [[ "$f" == "$PWD/new/drafts"/pr-round-1-* ]]
  [ -s "$f" ]
  [[ "$output" == *"--round-dir='$PWD/new/drafts'"* ]]
}

@test "--round-dir places the round file and is carried on the re-arm line" {
  review_burst
  local dir="$BATS_TEST_TMPDIR/drafts dir"; mkdir -p "$dir"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=reviewer \
    "--round-dir=$dir"
  [ "$status" -eq 0 ]
  local f; f=$(round_file)
  [[ "$f" == "$dir"/pr-round-1-* ]]
  [ -s "$f" ]
  [[ "$output" == *"--round-dir='$dir'"* ]]
}

# The case the flag exists for: a push and a reply in one burst. The reply is only
# ever reported here — the caller re-arms with since_iso set to now, so a payload
# it did not carry is filtered out for good.
@test "a push that lands with replies carries the replies" {
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
case "$1 $2" in
  "pr view")
    n=0; [ -f "$TICKS" ] && read -r n < "$TICKS"; n=$((n + 1)); echo "$n" > "$TICKS"
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

# The header's contract: the re-arm line's `since` is the result's `now=`, one
# value, so a caller reading either gets the same next arm.
@test "the re-arm line's since is the result's now" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  local rearm
  rearm=$(grep -A1 '── re-arm ──' <<<"$output" | tail -1)
  [[ "$rearm" == *" $(sha40 0) ${lines[-1]##* now=} bot "* ]]
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
# It used to die here with no result line, because the verdict read had no
# counter of its own and dying beat reporting quiet. The malformed shape is now
# caught one layer down, where the payload is parsed at all, so it arrives as a
# named ERROR the caller can branch on — and it is caught once for every reader
# rather than by each in turn.
@test "a review the fetch cannot parse reports ERROR instead of reporting quiet" {
  printf '[{"submittedAt":"1970-01-02T00:00:00Z","author":{"login":"someone"},"state":"APPROVED","commit":5}]' \
    > "$REVIEWS"
  INTERVAL=1 WINDOW=30 FAIL_MAX=2 FAIL_MIN_SECONDS=0 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --last-verdict= --role=reviewer
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"result=ERROR reason=pr-view-shape"* ]]
  [[ "$output" != *"result=IDLE"* ]]
}

# --- the author role's merge-state results -----------------------------------
#
# One arming covers a PR from open to merge, so a caller never swaps watchers
# after a clean review — the swap is what drops a review posted after an
# approval, and these cases are what make swapping unnecessary.

@test "a merged PR stops the watch" {
  echo MERGED > "$PRSTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CLOSED state=MERGED act=cleanup" ]]
}

@test "a PR closed without merging stops the watch" {
  echo CLOSED > "$PRSTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CLOSED state=CLOSED act=cleanup" ]]
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

# Nothing running, nothing red, the approval in hand — so only a human moves it.
# `--merge-stage` because a terminal block is an answer only once the review is
# over; during one it is the ordinary state of a PR with an open thread.
@test "a block with nothing pending is terminal and reaches the author" {
  echo BLOCKED > "$MERGESTATE"
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
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

# --- the check baseline is what the caller has been TOLD, not the last reading ---

# A recovery has to clear it. Carrying the old list forward means the same check
# failing a second time compares equal and is never reported again, for the life
# of the watch chain.
@test "a recovered check clears the baseline the re-arm carries" {
  echo '[]' > "$ROLLUP"
  INTERVAL=1 WINDOW=3 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --last-checks=lint
  [[ "$output" == *"--last-checks=''"* ]]
  [[ "$output" != *"lint"* ]]
}

@test "a failure the caller was told about is carried as handled" {
  echo '[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=5 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='lint'"* ]]
  [[ "$output" == *"--last-checks='lint'"* ]]
  # Paired with the head it was read on, or the next arm cannot tell this set
  # from one belonging to an earlier commit.
  [[ "$output" == *"--last-checks-head=$(sha40 0)"* ]]
}

# --- and it is only what they were told about THIS commit ----------------------

# The author's post-push re-arm carries the new head with the previous head's
# check names. Matched on names alone the second red build compares equal and is
# swallowed, so the author is never told the commit they just pushed is red.
@test "a check red on both sides of a push is reported again on the new head" {
  echo 1 > "$HEADCOUNT"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 1)" 2999-01-01T00:00:00Z bot \
    --role=author --last-checks=ci --last-checks-head="$(sha40 0)"
  [[ "${lines[-1]}" == "result=CHECKS checks='ci'"* ]]
  [[ "$output" == *"--last-checks-head=$(sha40 1)"* ]]
}

# The inverse, which is the behaviour the pairing must not cost: on the head the
# names were read on, a standing failure is still handled and does not wake the
# caller a second time.
@test "a standing failure on the same head stays suppressed" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --last-checks=ci --last-checks-head="$(sha40 0)"
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" != *"checks="* ]]
}

# A baseline with no head is one armed by hand or by a caller that predates the
# pairing. It cannot be placed on any commit, so it is void — a redundant wake,
# never a silent drop.
@test "a baseline with no head is not trusted" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --last-checks=ci
  [[ "${lines[-1]}" == "result=CHECKS checks='ci'"* ]]
}

# A check going red while a burst is settling must not be dropped in favour of
# the burst, and must not be marked handled without being reported. Riding along
# as a field on whatever the burst reports satisfies both: the caller is told,
# so advancing the baseline is then correct.
@test "a check going red during a settle rides out on the burst" {
  printf '%s' "$(reviews COMMENTED "$(sha40 0)" someone)" > "$REVIEWS"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=2 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 1970-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "${lines[-1]}" == *"checks='ci'"* ]]
  [[ "$output" == *"--last-checks='ci'"* ]]
}

# A wake that is only a red build still says so in the result name, so a caller
# branching on `result=` does not have to read the fields to find it.
@test "a check failing alone reports CHECKS" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='ci'"* ]]
}

# The baseline has to advance in-run too. Left un-advanced, the same standing
# verdict counts as a change on every tick, pushing the settle out faster than
# the poll floor can reach it — so the burst is only ever released by the cap.
@test "a standing verdict is reported at the settle, not held to the cap" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=3 SETTLE_MAX=600 WINDOW=60 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author --last-verdict=
  [[ "$output" == *"verdict=APPROVED"* ]]
  [ "$(cat "$TICKS")" -lt 20 ]
}

# --- what a settle may still be holding when it expires -----------------------

# The settle outlives its own reason: a check goes red, the settle starts, and the
# build is green again before it expires. Reporting the burst anyway names a red
# check the caller would find green, and then marks it handled — so the same check
# failing again compares equal to the baseline and is never reported at all.
@test "a check that recovers inside its own settle is not reported" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$ROLLUP" \
    AT_TICK_VALUE='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    INTERVAL=1 SETTLE=3 WINDOW=12 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" != *"checks="* ]]
  # The withdrawn failure must not be carried as handled either, or the next
  # genuine failure of the same check compares equal and is swallowed.
  [[ "$output" == *"--last-checks=''"* ]]
}

# The settle emptying must not fall through to the generic branch of the burst,
# which reports `activity=1` unconditionally.
@test "an emptied settle does not invent activity" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$ROLLUP" AT_TICK_VALUE='[]' \
    INTERVAL=1 SETTLE=3 WINDOW=12 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "$output" != *"result=ACTIVITY"* ]]
}

# --- a check re-run on the same head --------------------------------------------

# Marking a PR ready starts a second run that cancels the first on the same head;
# the cancelled run's checks stay in the rollup beside the live ones.
@test "a cancelled run superseded by a pending one is not a CHECKS wake" {
  echo '[{"name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"CANCELLED","startedAt":"2026-01-01T00:00:00Z"},
         {"name":"lint","workflowName":"CI","status":"IN_PROGRESS","conclusion":"","startedAt":"2026-01-01T00:01:00Z"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=6 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" != *"checks="* ]]
}

@test "a cancelled run superseded by a failed one names the check once" {
  echo '[{"name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"CANCELLED","startedAt":"2026-01-01T00:00:00Z"},
         {"name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-01-01T00:01:00Z"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='lint'"* ]]
}

# Until the live run's copy of a `needs:` job appears, the cancelled one is the
# newest there is.
@test "a cancelled check with no live copy yet is not a CHECKS wake" {
  echo '[{"name":"ci-required","workflowName":"CI","status":"COMPLETED","conclusion":"CANCELLED","startedAt":"0001-01-01T00:00:00Z","completedAt":"2026-01-01T00:01:00Z"},
         {"name":"lint","workflowName":"CI","status":"IN_PROGRESS","conclusion":"","startedAt":"2026-01-01T00:01:00Z"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=6 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" != *"checks="* ]]
}

@test "a failed run superseded by a pending one is not a CHECKS wake" {
  echo '[{"name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-01-01T00:00:00Z"},
         {"name":"lint","workflowName":"CI","status":"IN_PROGRESS","conclusion":"","startedAt":"2026-01-01T00:01:00Z"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=6 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" != *"checks="* ]]
}

@test "one name failing in two workflows is listed once" {
  echo '[{"name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-01-01T00:00:00Z"},
         {"name":"lint","workflowName":"Docs","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-01-01T00:00:00Z"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='lint'"* ]]
}

# --- check names are forge-supplied text ---------------------------------------

# `build (macos-latest)` is what GitHub calls a default matrix job. Unquoted it
# makes the re-arm line a syntax error rather than a command, and splits the
# result line into fields a caller cannot parse.
@test "a check name containing a space keeps the re-arm line runnable" {
  echo '[{"name":"build (macos-latest)","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='build (macos-latest)'"* ]]
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  # The contract is that a caller runs this line verbatim.
  bash -n <<<"$rearm"
}

@test "a check name containing a quote is escaped, not merely wrapped" {
  echo '[{"name":"dans lint","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  printf '%s' '[{"name":"it'"'"'s red","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  bash -n <<<"$rearm"
  # And it survives the round trip: the name the next arm parses back out has to
  # equal this one, or the standing failure is reported again forever.
  [[ "$rearm" == *"--last-checks='it'\\''s red'"* ]]
}

# --- naming the failing test, so a caller need not dig it out of the log --------

# The log lines are as the jobs endpoint serves them: a timestamp ahead of the
# runner's own output, which may be coloured. The check name carries a comma, as
# a two-axis matrix job's does.
@test "a checks-only wake names the failing tests from the job log" {
  echo '[{"name":"test (ubuntu, 20)","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/11/job/22"}]' > "$ROLLUP"
  printf '2026-10-16T02:12:45Z ok 382 a passing test\n' > "$RUNLOG"
  printf '2026-10-16T02:12:45Z not ok 383 the reaper kills a process\r\n' >> "$RUNLOG"
  printf '2026-10-16T02:12:46Z #   printf "not ok 9 echoed by a test"\n' >> "$RUNLOG"
  printf '2026-10-16T02:12:47Z \033[31mnot ok 390 - it'"'"'s red, twice\033[0m\n' >> "$RUNLOG"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='test (ubuntu, 20)' failed_tests='the reaper kills a process; it'\\''s red, twice' act=fix now="* ]]
  grep -q "api --allow-escape-sequences repos/o/r/actions/jobs/22/logs" "$CALLS"
}

# A status context's link is not an Actions job, so there is no log to read.
@test "a failing check with no Actions job link leaves failed_tests off" {
  echo '[{"context":"ci/legacy","state":"FAILURE","targetUrl":"https://ci.example.test/build/7"}]' > "$ROLLUP"
  printf '2026-10-16T02:12:45Z not ok 1 never read\n' > "$RUNLOG"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='ci/legacy' act=fix now="* ]]
  ! grep -q "actions/jobs" "$CALLS"
}

# Best effort: a log gh cannot fetch costs the field, never the report.
@test "a failed log that cannot be read leaves failed_tests off" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/11/job/22"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='ci' act=fix now="* ]]
}

# --- a block only a human clears is not a state to re-arm on -------------------

# BLOCKED covers "no approval yet" as well as "a required check failed", and the
# author watch is armed at `gh pr ready` — before any review exists. Read as
# terminal, the watch exits on its first tick on every repo that requires an
# approval, which is the watch's entire job.
@test "a block waiting on a required review is not terminal" {
  echo BLOCKED > "$MERGESTATE"
  echo REVIEW_REQUIRED > "$REVIEWDECISION"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
}

# Same shape after a findings round: the decision stays CHANGES_REQUESTED until a
# re-review, so treating it as terminal kills every watch armed after a push.
@test "a block waiting on a re-review is not terminal" {
  echo BLOCKED > "$MERGESTATE"
  echo CHANGES_REQUESTED > "$REVIEWDECISION"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
}

@test "a block with the approval in hand and nothing pending is still terminal" {
  echo BLOCKED > "$MERGESTATE"
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=BLOCKED cause=terminal"* ]]
}

# Neither clears without a human, so a caller that re-arms from the printed line
# — which is what both skills instruct — wakes on the same state every tick.
@test "DIRTY and a terminal block carry no re-arm line" {
  echo DIRTY > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=DIRTY* ]]
  [[ "$output" != *"re-arm"* ]]

  echo BLOCKED > "$MERGESTATE"; echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == result=BLOCKED* ]]
  [[ "$output" != *"re-arm"* ]]
}

# --- the window default is role-dependent, and it is load-bearing --------------

# lib-poll.sh applies its own WINDOW default at source time, so a role default set
# after the source never fires. Nothing else catches it: every other test in this
# file passes WINDOW explicitly, and the symptom is a 30-minute author watch
# silently becoming a 6-hour one.
@test "the author role gets the short window without being told" {
  INTERVAL=1000 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
}

# A standing failure is level state: it stays set until reported, so charging it
# to `changed` on every tick resets the backoff curve on every tick. On a draft
# hold the burst is never released, so nothing ever clears it and the poll sits
# at the curve's floor for the whole window — with the default 6h window, tens of
# times the requests the curve exists to avoid.
@test "a standing check failure does not pin the poll to the curve floor" {
  echo true > "$DRAFT_FILE"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  POLL_CURVE="0:1 5:8" WINDOW=12 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author --was-draft
  # The curve must advance past its floor. Pinned, every gap is the floor value.
  local naps; naps=$(grep -c ' 1$' "$CALLS" || true)
  [[ "${lines[-1]}" == result=IDLE* ]]
  # Four ticks on this curve and window, not twelve.
  [ "$(grep -c 'pr view' "$CALLS")" -le 6 ]
}

# A red check must not end the watch. `checks_failing` is separated from
# `terminal` in the fetch precisely so the CHECKS path handles it — a terminal
# block prints no re-arm line, so reaching it here stops the author's review
# watch permanently the first time CI goes red.
@test "a red required check reports CHECKS, not a terminal block" {
  echo BLOCKED > "$MERGESTATE"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=CHECKS checks='ci'"* ]]
  # And the watch stays armable, which a terminal block would not be.
  [[ "$output" == *"re-arm"* ]]
}

# --- a run that reports nothing has handled nothing ----------------------------

# The draft hold gates the burst but not the window, so IDLE is reachable with
# activity in hand. Advancing `since` there deletes it: the next arm filters it
# out and no run ever reports it.
@test "an IDLE holding a burst re-arms with the state it was given" {
  echo true > "$DRAFT_FILE"
  cat > "$STUB/comments" <<'EOF'
EOF
  printf '%s' '[{"state":"COMMENTED","submittedAt":"2026-06-01T00:00:00Z","author":{"login":"someone"},"commit":{"oid":"x"}}]' > "$REVIEWS"
  INTERVAL=1 SETTLE=30 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot --role=reviewer --was-draft
  [[ "${lines[-1]}" == result=IDLE* ]]
  # `since` must be the one passed in, not this run's `now`.
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == *"2026-01-01T00:00:00Z"* ]]
  # And the result line says so, for a caller that reads it rather than the line.
  [[ "${lines[-1]}" == *" since=2026-01-01T00:00:00Z act=rearm now="* ]]
}

# A quiet IDLE still advances, which is the whole re-arm contract.
@test "an IDLE holding nothing advances since as usual" {
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=IDLE* ]]
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" != *"2026-01-01T00:00:00Z"* ]]
  [[ "${lines[-1]}" != *" since="* ]]
}

# --- the verdict field means "stands at HEAD" ----------------------------------

# A push moves HEAD past the verdict seen earlier in the same run. Carrying the
# field onto that push's report says the new head is approved when nobody has
# read it — the one claim a caller acts on without fetching.
@test "a verdict is not reported alongside the push that invalidated it" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  AT_TICK=3 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=9 \
    INTERVAL=1 SETTLE=2 WINDOW=20 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer --last-verdict=
  [[ "${lines[-1]}" == result=COMMITS* ]]
  [[ "${lines[-1]}" != *"verdict="* ]]
}

# --- the re-arm line has to reproduce THIS watch, not a default one -------------

# `merge-wait.md` arms a six-hour wait explicitly and says in bold that the default
# will not do. A bare command drops that on the first wake, after which the skill
# reports a thirty-minute idle as six hours with no merge.
@test "the re-arm line carries the window this run was given" {
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == "WINDOW=4 "* ]]
  bash -n <<<"$rearm"
}

# A first arm passes `--last-verdict=` empty, meaning "none handled yet". With
# `:-` the default fires on that empty value, so a held verdict is handed back as
# handled and no run ever reports it.
@test "an IDLE holding a verdict does not hand it back as handled" {
  echo true > "$DRAFT_FILE"
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=30 WINDOW=8 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer \
      --was-draft --last-verdict=
  [[ "${lines[-1]}" == result=IDLE* ]]
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  # Nothing was reported, so the next arm must still have no verdict handled.
  [[ "$rearm" == *"--last-verdict= "* ]]
}

# --- a verdict outranks a red check as the result name -------------------------

# CHECKS sends the author to the build, not to the review, and the re-arm marks
# the verdict handled. So reducing an unhandled verdict to a CHECKS wake loses it
# until the IDLE backstop notices an approval at HEAD, a whole window later.
@test "a verdict standing at HEAD is not reduced to a CHECKS wake" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  echo '[{"name":"build","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author --last-verdict=
  [[ "${lines[-1]}" != result=CHECKS* ]]
  # The red build still rides along — it is not dropped, only demoted.
  [[ "${lines[-1]}" == *"checks='build'"* ]]
  [[ "${lines[-1]}" == *"verdict=APPROVED"* ]]
}

# --- a red build alone is not a reviewer wake ---------------------------------
#
# The reviewer's handling of one is a no-op, so the failure is held for the next
# burst that is a wake, and the baseline stays where the caller left it.

@test "a reviewer watch with only a check failing runs to IDLE, unadvanced" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "$output" != *"result=CHECKS"* ]]
  [[ "${lines[-1]}" == "result=IDLE act=rearm now="* ]]
  local rearm; rearm=$(grep -A1 '── re-arm ──' <<<"$output" | tail -1)
  # Its own `now=`, not a held `since=`: nothing was held back.
  [[ "$rearm" == *" $(sha40 0) ${lines[-1]##* now=} bot "* ]]
  [[ "$rearm" == *"--last-checks=''"* ]]
}

@test "a reviewer's held failure rides on the next comment and advances" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  AT_TICK=3 AT_TICK_FILE="$REVIEWS" \
    AT_TICK_VALUE='[{"state":"COMMENTED","submittedAt":"2026-06-01T00:00:00Z","author":{"login":"someone"},"commit":{"oid":"x"}}]' \
    INTERVAL=1 SETTLE=1 WINDOW=20 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot --role=reviewer
  [[ "$output" != *"result=CHECKS"* ]]
  [[ "${lines[-1]}" == "result=ACTIVITY "*"checks='ci'"* ]]
  local rearm; rearm=$(grep -A1 '── re-arm ──' <<<"$output" | tail -1)
  [[ "$rearm" == *"--last-checks='ci'"* ]]
}

@test "a reviewer's held failure rides on the next push and advances" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  AT_TICK=3 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=1 \
    INTERVAL=1 SETTLE=1 WINDOW=20 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "$output" != *"result=CHECKS"* ]]
  [[ "${lines[-1]}" == "result=COMMITS new_head=$(sha40 1) "*"checks='ci'"* ]]
  local rearm; rearm=$(grep -A1 '── re-arm ──' <<<"$output" | tail -1)
  [[ "$rearm" == *"--last-checks='ci' --last-checks-head=$(sha40 1)"* ]]
}

# With SETTLE=1 a checks-only settle would have released by the third tick, so a
# CLOSED reported bare is one the failure did not hold up or front.
@test "a reviewer's failing check does not front or delay CLOSED" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  AT_TICK=3 AT_TICK_FILE="$PRSTATE" AT_TICK_VALUE=MERGED \
    INTERVAL=1 SETTLE=1 WINDOW=20 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "result=CLOSED state=MERGED"* ]]
  [ "$(cat "$TICKS")" -eq 3 ]
}

# A settle long enough to be open when the reads start failing, which for the
# author reports the burst before the ERROR.
@test "a reviewer's failing check does not turn ERROR into a burst" {
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$FAIL_PRVIEW" AT_TICK_VALUE=x \
    INTERVAL=1 SETTLE=30 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [ "$(grep -c '^result=' <<<"$output")" -eq 1 ]
  [[ "${lines[-1]}" == "result=ERROR reason=pr-view"* ]]
  [[ "$output" != *"re-arm"* ]]
}

# --- what the caller has handled is advanced by a report, not by a sighting -----

# A verdict seen, then a push past it: the verdict is withdrawn and nothing is
# reported, so the next arm must still have no verdict handled. Advancing on
# sight suppresses that verdict if the head ever returns to the SHA.
@test "an unreported verdict does not advance what the caller has handled" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  AT_TICK=2 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=9 \
    INTERVAL=1 SETTLE=2 WINDOW=12 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author --last-verdict=
  [[ "${lines[-1]}" == result=IDLE* ]]
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == *"--last-verdict= "* ]]
}

# --- a degraded source must not empty the summary it feeds ---------------------

# The fetch substitutes `[]` for the inline half when that source fails. Taking
# it means a burst whose activity WAS inline comments reports `activity=1` over
# an empty summary.
@test "a degraded inline fetch does not blank the activity summary" {
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF'
read -r off < "$CLOCK"; echo "$(( CLOCK_BASE + off )) $*" >> "$CALLS"
if [ "$2" = view ]; then
  t=0; [ -f "$TICKS" ] && read -r t < "$TICKS"; t=$((t + 1)); echo "$t" > "$TICKS"
fi
case "$1 $2" in
  "pr view")
    printf '{"state":"OPEN","isDraft":false,"headRefOid":"%040d","reviews":[],"comments":[],"statusCheckRollup":[],"mergeStateStatus":"CLEAN","reviewDecision":""}' 0 ;;
  "api "*|"api")
    # Answers on tick 1, then goes blind — the degraded case.
    t=0; [ -f "$TICKS" ] && read -r t < "$TICKS"
    [ "$t" -ge 2 ] && exit 1
    echo '[{"user":{"login":"someone"},"created_at":"2026-06-01T00:00:00Z","id":7,"path":"a.sh","line":3,"body":"x"}]' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 SETTLE=3 WINDOW=12 FAIL_MAX=99 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  # The summary must still name the inline finding that caused the wake.
  [[ "$output" == *'"kind":"inline"'* ]]
}

# --- <last_head> is what the caller HANDLED, not what the run saw --------------

# The author role does not wake on a push. That must not also mean the push is
# skipped: the re-arm's head is the base of the next round's diff, so advancing it
# past a commit nobody reported leaves that commit in no diff at all.
@test "an unreported push does not advance the head the next round diffs from" {
  AT_TICK=2 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=7 \
    INTERVAL=1 WINDOW=6 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == *"o/r 1 $(sha40 0) "* ]]
}

# The reviewer role reports it, and a reported move IS handled, so there the head
# advances — otherwise every later round re-diffs from the original base.
@test "a reported push does advance it" {
  AT_TICK=2 AT_TICK_FILE="$HEADCOUNT" AT_TICK_VALUE=7 \
    INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=COMMITS* ]]
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == *"o/r 1 $(sha40 7) "* ]]
}

# --- a block the rollup cannot see yet -----------------------------------------

# The window between a push and the first check run has an EMPTY rollup, so
# nothing is counted as pending — and a merge watch is armed in exactly that
# window. Read as terminal it dies on its first tick, with no re-arm line.
@test "a required check that has not reported yet is not a terminal block" {
  echo BLOCKED > "$MERGESTATE"
  echo '[]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
}

@test "a base that moved on is not the reviewer's business" {
  echo BEHIND > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=IDLE* ]]
}

# --- activity= is a count of conversation, not of the burst --------------------

# A verdict is level-triggered, so it can fire with nothing else in the burst.
# The caller is told to go read comments when this says 1.
@test "a verdict-only burst does not claim conversation landed" {
  printf '%s' "$(reviews APPROVED "$(sha40 0)" someone)" > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author --last-verdict=
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "${lines[-1]}" == *"activity=0"* ]]
  [[ "${lines[-1]}" == *"verdict=APPROVED"* ]]
}

# --- a stop must not discard what the tick already held -------------------------

# The merge state is read after the tick's activity, so a comment landing in the
# same poll interval as a conflict is not answered with a bare DIRTY that carries
# no re-arm line — the caller would re-spawn off a fresh clock and filter it out.
@test "a conflict does not discard a comment from the same tick" {
  echo DIRTY > "$MERGESTATE"
  printf '%s' '[{"state":"COMMENTED","submittedAt":"2026-06-01T00:00:00Z","author":{"login":"someone"},"commit":{"oid":"x"}}]' > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "${lines[-1]}" == *"merge=DIRTY"* ]]
  # And it is re-armable, so the next tick delivers the bare stop.
  [[ "$output" == *"re-arm"* ]]
}

# With nothing in hand it is still a clean stop.
@test "a conflict with nothing in hand is still a bare stop" {
  echo DIRTY > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=DIRTY "* ]]
  [[ "$output" != *"re-arm"* ]]
}

# --- a base that moved on is not the end of the merge wait ----------------------

# One "Update branch" click clears it, and under a merge queue often nothing
# does. Ending the wait on it loses the merge the stage exists to catch.
@test "a base that moved on does not end the wait" {
  echo BEHIND > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" == *"merge=behind"* ]]
  [[ "$output" == *"re-arm"* ]]
}

# --- the reported set is the set that is actually red ---------------------------

# A partial recovery can bring the failing set back to exactly what the caller was
# already told. Naming the pre-recovery set reports a check they will find green,
# and advances the baseline onto a set that never existed — after which the still-
# red one compares unequal and is reported a second time.
@test "a partial recovery does not report a check that went green" {
  echo '[{"name":"a","status":"COMPLETED","conclusion":"FAILURE"},
         {"name":"b","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$ROLLUP" \
    AT_TICK_VALUE='[{"name":"a","status":"COMPLETED","conclusion":"FAILURE"},
                    {"name":"b","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    INTERVAL=1 SETTLE=3 WINDOW=12 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author \
      --last-checks=a --last-checks-head="$(sha40 0)"
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "$output" != *"checks='a,b'"* ]]
  # The baseline stays what the caller was told, so `a` is not re-reported later.
  [[ "$output" == *"--last-checks='a'"* ]]
}

# --- a red build is not a round to spend ----------------------------------------

# The round is four requests over the diff, bodies and threads, and a red build
# is neither a re-review nor a finding to answer.
@test "a checks-only wake neither fetches nor offers a pr-round" {
  fake_round <<'STUB'
echo ran >> "$ROUND_CALLS"
echo result=OK
STUB
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$SCRIPTS/watch-pr.sh" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=CHECKS* ]]
  [[ "$output" != *"── next ──"* ]]
  [[ "$output" != *"── round ──"* ]]
  [ ! -e "$ROUND_CALLS" ]
  # The re-arm line is still there — that is how the watch continues.
  [[ "$output" == *"re-arm"* ]]
}

# A burst with conversation in it still gets one.
@test "a burst with conversation still offers a pr-round" {
  printf '%s' '[{"state":"COMMENTED","submittedAt":"2026-06-01T00:00:00Z","author":{"login":"someone"},"commit":{"oid":"x"}}]' > "$REVIEWS"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "$output" == *"── round ──"* ]]
}

# --- a blocked PR is the normal state of one under review ----------------------

# With `required_conversation_resolution` on, one open thread makes GitHub report
# BLOCKED; with no required approver `reviewDecision` is empty, so the cause falls
# through to terminal. Stopping there ends the review watch on its first tick,
# every round, for the ordinary reason that a reviewer has opened a thread.
@test "a terminal block does not end a review-stage watch" {
  echo BLOCKED > "$MERGESTATE"
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  # Named, not swallowed — the window's own IDLE says why nothing is moving.
  [[ "${lines[-1]}" == *"merge=blocked"* ]]
  [[ "$output" == *"re-arm"* ]]
}

# Once the review is over the same state IS the answer: nothing pending clears it.
@test "a terminal block does end a merge-stage watch" {
  echo BLOCKED > "$MERGESTATE"
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=BLOCKED cause=terminal"* ]]
  [[ "$output" != *"re-arm"* ]]
}

# One poll can see every check done and the PR still BLOCKED, a terminal reading
# on a PR that is clean seconds later. Stopping on it ends the merge wait with no
# re-arm line, and the merge then goes uncaught.
@test "a terminal block that clears on the confirming read does not stop a merge-stage watch" {
  echo BLOCKED > "$MERGESTATE"
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$MERGESTATE" AT_TICK_VALUE=CLEAN \
    INTERVAL=60 WINDOW=30 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "$output" != *"result=BLOCKED"* ]]
  [[ "${lines[-1]}" == result=IDLE* ]]
  # The confirming read is the fixed delay, not the curve's minute.
  [ "$(grep ' pr view ' "$CALLS" | sed -n 2p | cut -d' ' -f1)" = $(( CLOCK_BASE + 10 )) ]
}

@test "a terminal block that persists across the confirming read stops a merge-stage watch" {
  echo BLOCKED > "$MERGESTATE"
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  local log="$BATS_TEST_TMPDIR/trace.log"
  WATCH_LOG="$log" INTERVAL=60 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=BLOCKED cause=terminal"* ]]
  [[ "$output" != *"re-arm"* ]]
  [ "$(grep -c ' pr view ' "$CALLS")" -eq 2 ]
  [ "$(grep ' pr view ' "$CALLS" | sed -n 2p | cut -d' ' -f1)" = $(( CLOCK_BASE + 10 )) ]
  # The trace records what the stopping poll saw, which the result line does not.
  grep -q 'stop result=BLOCKED merge=blocked cause=terminal' "$log"
}

# Only two terminal reads in a row confirm. The observed shape began with a check
# still running, which is a wait, so the first terminal read after it is the one
# that needs confirming, not the confirmation.
@test "a wait before the first terminal read does not count toward confirming it" {
  echo BLOCKED > "$MERGESTATE"
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"IN_PROGRESS","conclusion":""}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$ROLLUP" \
    AT_TICK_VALUE='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' \
    INTERVAL=1 WINDOW=30 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=BLOCKED cause=terminal"* ]]
  [ "$(grep -c ' pr view ' "$CALLS")" -eq 3 ]
}

# A read in between that is anything but terminal starts the confirmation over,
# so a terminal read after it is a first sighting again, not the second.
@test "a non-terminal read between two terminal reads restarts the confirmation" {
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  # Merge state per poll, the last line holding for every poll after it.
  export SEQ="$BATS_TEST_TMPDIR/seq"
  printf '%s\n' BLOCKED CLEAN BLOCKED BLOCKED > "$SEQ"
  mv "$STUB/gh" "$STUB/gh.stub"
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'EOF2'
if [ "$1 $2" = "pr view" ]; then
  t=0; [ -f "$TICKS" ] && read -r t < "$TICKS"
  sed -n "$(( t + 1 ))p" "$SEQ" | grep . > "$MERGESTATE.next" \
    && mv "$MERGESTATE.next" "$MERGESTATE"
fi
exec "$(dirname "$0")/gh.stub" "$@"
EOF2
  chmod +x "$STUB/gh"
  INTERVAL=1 WINDOW=60 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=BLOCKED cause=terminal"* ]]
  [ "$(grep -c ' pr view ' "$CALLS")" -eq 4 ]
}

# The window can close between the first terminal read and its confirmation. The
# IDLE then still says the PR read as blocked, as it does at the review stage.
@test "a merge-stage window closing before the confirming read names the block on its IDLE" {
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$MERGESTATE" AT_TICK_VALUE=BLOCKED \
    INTERVAL=5 WINDOW=5 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=IDLE merge=blocked"* ]]
  [[ "$output" == *"re-arm"* ]]
}

@test "a TERMINAL_CONFIRM that is not a positive whole number is refused" {
  TERMINAL_CONFIRM=0 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=ERROR reason=bad-args"* ]]
}

# The stage has to survive the re-arm, or the first wake silently drops the merge
# wait back to review-stage behaviour and the terminal block never lands.
@test "the merge stage is carried on the re-arm line" {
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == *"--merge-stage"* ]]
  bash -n <<<"$rearm"
}

# A conflict is never the normal state of a PR and nothing the reviewer does
# clears it, so it stops at either stage.
@test "a conflict stops a review-stage watch too" {
  echo DIRTY > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == "result=DIRTY "* ]]
}

# The third `merge=` value, and the one whose whole purpose is to be seen: a
# status GitHub has never documented means the schema moved, and the remedy is a
# person re-running the enum capture rather than another poll. Silent is the one
# thing it must not be, and the other two arms are pinned.
@test "an undocumented merge status is surfaced on the window's IDLE" {
  echo NEWLY_INVENTED > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=author
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" == *"merge=unrecognised:newly_invented"* ]]
}

# Scoped to the author, like the rest of the merge block — a reviewer has nothing
# to do about a merge status, and saying so on its IDLE would be noise.
@test "the reviewer's IDLE carries no merge field" {
  echo NEWLY_INVENTED > "$MERGESTATE"
  INTERVAL=1 WINDOW=4 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" != *"merge="* ]]
}

# A headless session stops a background command at its Bash `timeout`, and a watch
# stopped that way prints no result. So a window longer than lib-poll.sh's
# WINDOW_CEILING is served in runs: each ends itself at the ceiling with a re-arm
# line that carries the rest of the window, and running that line goes on with it.
@test "a window longer than the ceiling ends the run at the ceiling and re-arms the rest" {
  WINDOW=21600 WINDOW_CEILING=30 INTERVAL=7 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [ "$(cat "$CLOCK")" -le 30 ]
  [[ "${lines[-1]}" == "result=IDLE window_left=21570 act=rearm now="* ]]
  local rearm; rearm=$(grep -A1 '── re-arm ──' <<<"$output" | tail -1)
  [[ "$rearm" == "WINDOW=21600 WINDOW_LEFT=21570 \""* ]]

  WINDOW_CEILING=30 INTERVAL=7 run eval "$rearm"
  [[ "${lines[-1]}" == "result=IDLE window_left=21540 act=rearm now="* ]]
}

@test "the run that exhausts the window reports a bare IDLE and re-arms a full one" {
  WINDOW=21600 WINDOW_LEFT=10 WINDOW_CEILING=30 INTERVAL=1 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot --role=reviewer
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "result=IDLE act=rearm now="* ]]
  local rearm; rearm=$(grep -A1 '── re-arm ──' <<<"$output" | tail -1)
  [[ "$rearm" == "WINDOW=21600 \""* ]]
}

# The orchestrator arms no watch of its own, and its posts on a PR are addressed
# to the author and the reviewer, so its bot's conversation comment wakes both
# roles, in either spelling of its login. Its App has no `pull_requests`
# permission, so it posts no inline comment.
@test "an orchestrator bot comment wakes a reviewer watch and an author watch" {
  export ORCH_LOGIN
  { echo "#!$BASH"; cat; } > "$STUB/gh" <<'STUB'
case "$1 $2" in
  "pr view")
    printf '{"state":"OPEN","isDraft":false,"headRefOid":"%040d","reviews":[],"comments":[{"author":{"login":"%s"},"createdAt":"2999-01-01T00:00:00Z"}]}\n' 0 "$ORCH_LOGIN" ;;
  "api "*|"api") echo '[]' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$STUB/gh"
  local role slug
  for ORCH_LOGIN in agent-orchestrator-t 'agent-orchestrator-t[bot]'; do
    for role in reviewer:agent-reviewer-t author:agent-author-t; do
      slug="${role#*:}"; role="${role%%:*}"
      echo 0 > "$CLOCK"
      INTERVAL=1 SETTLE=1 WINDOW=10 \
        run "$WATCH" o/r 1 "$(sha40 0)" 2000-01-01T00:00:00Z "$slug" --role="$role"
      [[ "$output" == *"result=ACTIVITY"* ]] \
        || { echo "$ORCH_LOGIN did not wake the $role watch: $output"; return 1; }
    done
  done
}

# --- the author's login, from the role resolver ------------------------------

pr_comment() {  # <login> — one PR comment, after any since these tests arm with
  printf '[{"author":{"login":"%s"},"createdAt":"2026-01-02T00:00:00Z","body":"b"}]' "$1" > "$COMMENTS"
}

author_watch() {  # an author-side watch with no slug: the resolver supplies it
  INTERVAL=1 SETTLE=1 WINDOW=5 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z "" --role=author --last-verdict=
}

@test "with an author App, the author watch wakes on the operator's comment" {
  export DNBG_AUTHOR_APP_ID=7 DNBG_AUTHOR_SLUG=agent-author-t
  pr_comment operator
  author_watch
  [[ "$output" == *"result=ACTIVITY"* ]]
}

@test "with an author App, the author watch wakes on the orchestrator bot's comment" {
  export DNBG_AUTHOR_APP_ID=7 DNBG_AUTHOR_SLUG=agent-author-t
  pr_comment 'agent-orchestrator-t[bot]'
  author_watch
  [[ "$output" == *"result=ACTIVITY"* ]]
}

# The author's own posts, a `Delegated question:` among them, land under its bot.
@test "with an author App, the author watch ignores the author bot's own comment" {
  export DNBG_AUTHOR_APP_ID=7 DNBG_AUTHOR_SLUG=agent-author-t
  pr_comment 'agent-author-t[bot]'
  author_watch
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" == *" agent-author-t --role=author"* ]]
}

@test "with no author App, the author watch ignores the operator's comment, as before" {
  pr_comment operator
  author_watch
  [[ "$output" == *"result=IDLE"* ]]
  [[ "$output" == *" operator --role=author"* ]]
}

@test "an author watch whose login the resolver refuses says so, not bad-args" {
  export DNBG_AUTHOR_APP_ID=7   # configured, with no slug: no-login
  pr_comment operator
  author_watch
  [[ "$output" == *"result=ERROR reason=role"* ]]
}

# --- act=: the branch the caller's reference prescribes -----------------------
#
# One case per result × role × stage that the references handle differently:
# `reviewer/references/watch.md` for the reviewer, `watch-results.md` and
# `merge-wait.md` for the author. Each table there agrees with these. Where a
# reference branches on something the watch cannot see, the value is `read`.

# Sets the stub up so the watch returns <state>.
arrange() {  # <state>
  case "$1" in
    COMMITS)  echo 1 > "$HEADCOUNT" ;;
    ACTIVITY) printf '%s' '[{"state":"COMMENTED","submittedAt":"2026-06-01T00:00:00Z","author":{"login":"someone"},"commit":{"oid":"x"}}]' > "$REVIEWS" ;;
    CHECKS)   echo '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' > "$ROLLUP" ;;
    CLOSED)   echo MERGED > "$PRSTATE" ;;
    DIRTY)    echo DIRTY > "$MERGESTATE" ;;
    BEHIND)   echo BEHIND > "$MERGESTATE" ;;
    BLOCKED)  echo BLOCKED > "$MERGESTATE"; echo APPROVED > "$REVIEWDECISION"
              echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP" ;;
    ERROR)    touch "$FAIL_PRVIEW" ;;
    READY|IDLE) ;;   # READY comes from --was-draft on a PR that is not a draft
  esac
}

# Runs the watch on one arranged state and checks the result and its act=.
expect_act() {  # <state> <result-prefix> <act> <watch flags...>
  arrange "$1"; local want=$2 act=$3; shift 3
  INTERVAL=1 SETTLE=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=10 \
    run "$WATCH" o/r 1 "$(sha40 0)" 2026-01-01T00:00:00Z bot "$@"
  [[ "${lines[-1]}" == "result=$want"* ]]
  [[ "${lines[-1]} " == *" act=$act "* ]]
}

@test "act: a reviewer's COMMITS is a round" {
  expect_act COMMITS COMMITS round --role=reviewer
}
@test "act: a reviewer's ACTIVITY is a round" {
  expect_act ACTIVITY ACTIVITY round --role=reviewer
}
@test "act: a reviewer's READY is a round" {
  expect_act READY READY round --role=reviewer --was-draft
}
# A red build alone is no reviewer wake: the window ends on its IDLE.
@test "act: a reviewer's red build alone ends on an IDLE re-arm" {
  expect_act CHECKS IDLE rearm --role=reviewer
}
# watch.md: in issue mode CLOSED is the trigger to re-discover, and the watch
# cannot see the mode.
@test "act: a reviewer's CLOSED sends it to the reference" {
  expect_act CLOSED "CLOSED state=MERGED" read --role=reviewer
}
@test "act: a reviewer's IDLE is a re-arm" {
  expect_act IDLE IDLE rearm --role=reviewer
}
@test "act: a reviewer's ERROR sends it to the reference" {
  expect_act ERROR ERROR read --role=reviewer
}

@test "act: an author's ACTIVITY is a round, at either stage" {
  expect_act ACTIVITY ACTIVITY round --role=author
  expect_act ACTIVITY ACTIVITY round --role=author --merge-stage
}
@test "act: an author's READY is a round" {
  expect_act READY READY round --role=author --was-draft
}
@test "act: an author's CHECKS is a fix, at either stage" {
  expect_act CHECKS "CHECKS checks='ci'" fix --role=author
  expect_act CHECKS "CHECKS checks='ci'" fix --role=author --merge-stage
}
@test "act: an author's CLOSED is the cleanup, at either stage" {
  expect_act CLOSED "CLOSED state=MERGED" cleanup --role=author
  expect_act CLOSED "CLOSED state=MERGED" cleanup --role=author --merge-stage
}
@test "act: an author's CLOSED unmerged is the cleanup too" {
  echo CLOSED > "$PRSTATE"
  expect_act IDLE "CLOSED state=CLOSED" cleanup --role=author
}
# A stacked PR whose base moved is rebased rather than asked about, and the
# watch cannot see that the PR is stacked.
@test "act: an author's DIRTY sends it to the reference, at either stage" {
  expect_act DIRTY "DIRTY " read --role=author
  expect_act DIRTY "DIRTY " read --role=author --merge-stage
}
# The round comes first; the bare stop follows on the next run.
@test "act: a burst carrying merge=DIRTY is a round" {
  arrange DIRTY
  expect_act ACTIVITY ACTIVITY round --role=author
  [[ "${lines[-1]}" == *"merge=DIRTY"* ]]
}
@test "act: an author's terminal BLOCKED is a report" {
  expect_act BLOCKED "BLOCKED cause=terminal" report --role=author --merge-stage
}
# watch-results.md: at the review stage, do not silently re-arm.
@test "act: an author's review-stage IDLE is a report, merge= or not" {
  expect_act IDLE IDLE report --role=author
  expect_act BEHIND "IDLE merge=behind" report --role=author
}
# merge-wait.md: six hours with no merge is reported; an IDLE whose merge=
# names a cause is re-armed.
@test "act: an author's bare merge-stage IDLE is a report" {
  expect_act IDLE IDLE report --role=author --merge-stage
}
@test "act: an author's merge-stage IDLE naming a cause is a re-arm" {
  expect_act BEHIND "IDLE merge=behind" rearm --role=author --merge-stage
}
@test "act: a merge-stage IDLE naming an unconfirmed block is a re-arm" {
  echo APPROVED > "$REVIEWDECISION"
  echo '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' > "$ROLLUP"
  AT_TICK=2 AT_TICK_FILE="$MERGESTATE" AT_TICK_VALUE=BLOCKED \
    INTERVAL=5 WINDOW=5 run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot \
    --role=author --merge-stage
  [[ "${lines[-1]}" == "result=IDLE merge=blocked"*" act=rearm "* ]]
}
@test "act: an IDLE cut short at the ceiling is a re-arm for every role and stage" {
  local flags
  for flags in --role=reviewer --role=author "--role=author --merge-stage"; do
    # shellcheck disable=SC2086  # flags is a deliberately split list
    WINDOW=21600 WINDOW_CEILING=30 INTERVAL=7 \
      run "$WATCH" o/r 1 "$(sha40 0)" 2999-01-01T00:00:00Z bot $flags
    [[ "${lines[-1]}" == "result=IDLE window_left="*" act=rearm now="* ]]
  done
}
@test "act: an author's ERROR sends it to the reference, whatever the reason" {
  expect_act ERROR ERROR read --role=author
  rm "$FAIL_PRVIEW"
  expect_act IDLE "ERROR reason=bad-args" read --role=author --bogus
}
