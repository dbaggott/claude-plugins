#!/usr/bin/env bats
#
# Tests for the shared PR/issue watcher. `gh` is stubbed on PATH, so these
# exercise the loop's own logic — failure counting, the backoff curve, and how
# the two interact — without touching the network.
#
# Timing matters in several cases, so the intervals are driven down to seconds
# via the same env overrides the script documents.

WATCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/watch-pr.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  # MODE_* files control the stub: presence means "this source fails".
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "$(date +%s) $*" >> "$CALLS"
case "$1 $2" in
  "pr view")
    [ -f "$FAIL_PRVIEW" ] && exit 1
    n=$(cat "$HEADCOUNT" 2>/dev/null || echo 0)
    printf '{"state":"OPEN","isDraft":false,"headRefOid":"sha%s","reviews":[],"comments":[]}' "$n" ;;
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
}

# (a) every poll fails -> exactly one ERROR, and never IDLE.
@test "a source failing FAIL_MAX times reports ERROR, not IDLE" {
  touch "$FAIL_PRVIEW"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
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
             echo '{"state":"OPEN","isDraft":false,"headRefOid":"sha0","reviews":[],"comments":[]}' ;;
  *) echo '[]' ;;
esac
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=3 run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
  [[ "$output" != *"result=ERROR"* ]]
  [[ "$output" == *"result=IDLE"* ]]
}

# (c) the insidious one: the primary poll stays healthy, so the watch looks fine
# while thread replies silently never register.
@test "a failing comments query reports ERROR naming that source" {
  touch "$FAIL_COMMENTS"
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
  [[ "$output" == *"result=ERROR"* ]]
  [[ "$output" == *"reason=comments"* ]]
}

# (d) the curve: gaps widen while nothing happens, and collapse on a change.
# POLL_CURVE is the real knob (lib-poll.sh); tests/lib-poll.bats covers its shape
# as a pure function, so what's being checked here is that the watch actually
# drives it — that quiet widens the gap and a change resets it.
@test "the interval grows while quiet and returns to the floor on a change" {
  ( sleep 4; echo 1 > "$HEADCOUNT" ) &
  POLL_CURVE="0:1 3:4" SETTLE=1 WINDOW=20 \
    run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
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
  ( sleep 6; touch "$FAIL_PRVIEW" ) &
  start=$(date +%s)
  POLL_CURVE="0:1 2:8" FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 \
    run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
  elapsed=$(( $(date +%s) - start ))
  [[ "$output" == *"result=ERROR"* ]]
  # 3 failures at the 1s floor is ~3s after the failures start (~6s in). Without
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
  "pr view") echo '{"state":"OPEN","isDraft":false,"headRefOid":"sha9","reviews":[],"comments":[]}' ;;
  *) exit 1 ;;   # comments query always fails
esac
EOF
  chmod +x "$STUB/gh"
  # The head differs from the armed LAST_HEAD, so a burst starts on tick 1.
  # SETTLE is long enough that it cannot settle on its own before FAIL_MAX trips.
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 SETTLE=120 SETTLE_MAX=120 WINDOW=60 \
    run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
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
  INTERVAL=1 FAIL_MAX=3 FAIL_MIN_SECONDS=0 WINDOW=60 run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
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
  INTERVAL=1 FAIL_MAX=99 FAIL_MIN_SECONDS=0 WINDOW=2 run "$WATCH" o/r 1 sha0 1970-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  [[ "$output" == *"result="* ]]
}

# issue mode shares the loop; only what it polls differs.
@test "--issue wakes when a linked PR appears" {
  ( sleep 2; echo '[{"number":9}]' > "$LINKED" ) &
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
  "pr view") echo '{"state":"OPEN","isDraft":false,"headRefOid":"sha0","reviews":[],"comments":[]}' ;;
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
  INTERVAL=1 SETTLE=1 WINDOW=10 run "$WATCH" o/r 1 sha0 2000-01-01T00:00:00Z bot
  [ "$status" -eq 0 ]
  # Drop direction=desc and this is result=IDLE with a real reply unseen.
  [[ "$output" == *"result=ACTIVITY"* ]]
}
