#!/usr/bin/env bats
#
# Tests for the per-tick PR fetch. `gh` is stubbed on PATH and serves whatever
# JSON the test writes, so every branch is reachable without a network.
#
# The mapping from GitHub's `mergeStateStatus` to a cause is the reason this
# script exists rather than the watcher reading the field directly: GitLab names
# the cause and GitHub overloads one status, so the counting that tells a
# still-running required check from a failed one is a GitHub detail and must not
# reach a caller. Every case below is one a caller would otherwise have to make.

FETCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/fetch-pr-state.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export PR_JSON="$BATS_TEST_TMPDIR/pr.json"
  export INLINE_JSON="$BATS_TEST_TMPDIR/inline.json"
  export FAIL_PR="$BATS_TEST_TMPDIR/fail_pr"
  export FAIL_INLINE="$BATS_TEST_TMPDIR/fail_inline"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*)             [ -f "$FAIL_PR" ] && exit 1;     cat "$PR_JSON" ;;
  *"pulls/"*"/comments"*)  [ -f "$FAIL_INLINE" ] && exit 1; cat "$INLINE_JSON" ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  echo '[]' > "$INLINE_JSON"
}

# A minimal open PR, with the rollup and merge status the case is about.
pr() {  # <mergeStateStatus> <rollup-json> [reviewDecision]
  jq -cn --arg m "$1" --argjson rollup "$2" --arg rd "${3:-}" \
    '{state:"OPEN", isDraft:false,
      headRefOid:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      reviews:[], comments:[], statusCheckRollup:$rollup, mergeStateStatus:$m,
      reviewDecision:$rd}' > "$PR_JSON"
}

obj() { sed '$d' <<<"$1"; }        # everything above the result line
line() { tail -1 <<<"$1"; }

@test "a clean PR reports no cause" {
  pr CLEAN '[]'
  run "$FETCH" o/r 1
  [ "$status" -eq 0 ]
  [ "$(obj "$output" | jq -r '.merge.status')" = clean ]
  [ "$(obj "$output" | jq -r '.merge.cause')" = null ]
}

@test "BLOCKED with a check still running is a transient block, not a terminal one" {
  pr BLOCKED '[{"name":"e2e","status":"IN_PROGRESS","conclusion":""}]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_running ]
}

# The distinction the caller cannot make for itself: both arrive as BLOCKED, and
# one means "wait for the run to finish", the other "the build is red".
@test "BLOCKED with everything finished is not a wait" {
  pr BLOCKED '[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_failing ]
}

@test "a cancelled or timed-out check counts as finished, not as still running" {
  pr BLOCKED '[{"name":"a","status":"COMPLETED","conclusion":"CANCELLED"},
               {"name":"b","status":"COMPLETED","conclusion":"TIMED_OUT"}]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_failing ]
}

@test "a neutral check does not make a clean PR look unfinished" {
  pr BLOCKED '[{"name":"skipped","status":"COMPLETED","conclusion":"NEUTRAL"}]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = terminal ]
}

# Four states out, whatever the forge calls them. A running CheckRun and a
# PENDING StatusContext are the same thing to a caller, and a caller that had to
# tell them apart would read one of them as failed.
@test "check states are normalised to success, failure, pending or neutral" {
  pr BLOCKED '[{"name":"a","status":"COMPLETED","conclusion":"SUCCESS"},
               {"name":"b","status":"IN_PROGRESS","conclusion":""},
               {"name":"c","status":"COMPLETED","conclusion":"TIMED_OUT"},
               {"name":"d","status":"COMPLETED","conclusion":"SKIPPED"},
               {"context":"e","state":"PENDING"}]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '[.checks[].state] | join(",")')" = "success,pending,failure,neutral,pending" ]
}

# Two rollup shapes reach the same field. A StatusContext carries no
# `conclusion` at all, so a reader keying on that alone sees every legacy status
# as unfinished forever.
@test "the StatusContext shape is normalised like a CheckRun" {
  pr BLOCKED '[{"context":"ci/legacy","state":"PENDING"}]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.checks[0].name')" = "ci/legacy" ]
  [ "$(obj "$output" | jq -r '.checks[0].state')" = pending ]
}

@test "a PR with no checks at all is not read as having a pending one" {
  pr BLOCKED '[]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" != checks_running ]
  [ "$(obj "$output" | jq -r '.checks | length')" = 0 ]
}

# `tests/merge-cause.bats` owns the question of which values are documented; this
# only pins that an undocumented one is carried through by name rather than
# guessed at. `DRAFT` is a real example — it reads like a merge state and is not
# one, so a mapping written from memory tends to include it.
@test "an unrecognised merge status is carried by name rather than guessed" {
  pr DRAFT '[]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.status')" = unrecognised ]
  [ "$(obj "$output" | jq -r '.merge.cause')" = draft ]
}

# One source failing must not cost the tick every other source answered.
@test "inline comments failing degrades the object rather than losing it" {
  pr CLEAN '[]'
  touch "$FAIL_INLINE"
  run "$FETCH" o/r 1
  [[ "$(line "$output")" == "result=OK"*"degraded=inline-comments"* ]]
  [ "$(obj "$output" | jq -r '.state')" = OPEN ]
}

@test "a healthy tick reports no degradation" {
  pr CLEAN '[]'
  run "$FETCH" o/r 1
  [[ "$(line "$output")" != *degraded=* ]]
}

@test "the primary source failing is an error naming it" {
  pr CLEAN '[]'
  touch "$FAIL_PR"
  run "$FETCH" o/r 1
  [[ "$output" == *"result=ERROR reason=pr-view "* ]]
}

# An error body is well-formed JSON. Proving the payload parses is not proving
# the fields are there, and a missing `state` matches neither MERGED nor CLOSED
# for the life of a watch.
@test "an error body that parses is a shape error, not a quiet OPEN" {
  echo '{"message":"Not Found"}' > "$PR_JSON"
  run "$FETCH" o/r 1
  [[ "$output" == *"reason=pr-view-shape"* ]]
}

@test "a missing isDraft is a shape error rather than a null the caller compares" {
  jq -cn '{state:"OPEN", headRefOid:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
           reviews:[], comments:[], statusCheckRollup:[], mergeStateStatus:"CLEAN"}' > "$PR_JSON"
  run "$FETCH" o/r 1
  [[ "$output" == *"reason=pr-view-shape"* ]]
}

@test "unparseable output is a shape error, never a crash without a result line" {
  echo 'not json at all' > "$PR_JSON"
  run "$FETCH" o/r 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=pr-view-shape"* ]]
}

@test "a missing or non-numeric pr number is refused" {
  run "$FETCH" o/r
  [[ "$output" == *"reason=bad-args"* ]]
  run "$FETCH" o/r abc
  [[ "$output" == *"reason=bad-args"* ]]
}

# The seam https://github.com/dbaggott/claude-plugins/issues/149 widens. It must
# refuse rather than silently answer as GitHub.
@test "a forge with no backend is refused rather than assumed" {
  pr CLEAN '[]'
  FORGE=gitlab run "$FETCH" o/r 1
  [[ "$output" == *"reason=unsupported-forge"* ]]
}

@test "reviews and comments are normalised to forge-neutral names" {
  jq -cn '{state:"OPEN", isDraft:false, headRefOid:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
           reviews:[{author:{login:"r"}, submittedAt:"2026-01-01T00:00:00Z",
                     state:"APPROVED", commit:{oid:"bbb"}}],
           comments:[{author:{login:"c"}, createdAt:"2026-01-02T00:00:00Z"}],
           statusCheckRollup:[], mergeStateStatus:"CLEAN"}' > "$PR_JSON"
  echo '[{"user":{"login":"i"},"created_at":"2026-01-03T00:00:00Z","id":7,"path":"a.sh","line":3}]' \
    > "$INLINE_JSON"
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.reviews[0].author')" = r ]
  [ "$(obj "$output" | jq -r '.reviews[0].sha')" = bbb ]
  [ "$(obj "$output" | jq -r '.comments[0].author')" = c ]
  [ "$(obj "$output" | jq -r '.inline[0].id')" = 7 ]
  [ "$(obj "$output" | jq -r '.inline[0].path')" = a.sh ]
}

# BLOCKED covers a third wait the caller cannot see: a required review that has
# not been given. It reads exactly like a failed required check — nothing is
# pending either way — and a caller told "terminal" stops watching, which on the
# author side means exiting before the review it is waiting for can arrive.
@test "BLOCKED on a review that has not been given is not terminal" {
  pr BLOCKED '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' REVIEW_REQUIRED
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = review_required ]
}

# Same status after a findings round: the decision stays CHANGES_REQUESTED until
# a re-review, so reading it as terminal kills every watch armed after a push.
@test "BLOCKED on a re-review that has not happened is not terminal" {
  pr BLOCKED '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' CHANGES_REQUESTED
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = review_required ]
}

# What is left once both self-clearing causes are separated out: an approval in
# hand, nothing running, and still blocked — so only a human moves it.
@test "a red check outranks the approval state as the cause" {
  pr BLOCKED '[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]' APPROVED
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_failing ]
}

# A repo requiring no approval answers empty, which must not be read as a wait.
@test "BLOCKED on a repo that requires no approval is terminal" {
  pr BLOCKED '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' ""
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = terminal ]
}

# A check still running outranks the review wait: it is the more specific answer
# and the one that tells a caller the state will move on its own.
@test "a running check outranks a pending review as the cause" {
  pr BLOCKED '[{"name":"e2e","status":"IN_PROGRESS","conclusion":""}]' REVIEW_REQUIRED
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_running ]
}

# The skills' BLOCKED diagnostic reads the object with `head -1`, so a
# pretty-printed object makes the documented command a jq parse error at exactly
# the point the doc says never to guess a cause.
@test "the object is one line, so head -1 yields valid JSON" {
  pr CLEAN '[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]'
  run "$FETCH" o/r 1
  [ "${#lines[@]}" -eq 2 ]
  [ "$(printf '%s\n' "$output" | head -1 | jq -r '.checks[] | select(.state=="failure") | .name')" = lint ]
}

# The fourth wait that arrives as BLOCKED. On a repo with no required-approval
# protection `reviewDecision` is empty, so a failed required check reached the
# terminal fallback — and a terminal block prints no re-arm line, so the author's
# review watch ended permanently the first time CI went red.
@test "BLOCKED on a failed required check is not terminal" {
  pr BLOCKED '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}]' ""
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_failing ]
}

# A still-running check outranks a failed one: the state is still moving, so the
# caller has nothing to decide yet.
@test "a running check outranks a failed one as the cause" {
  pr BLOCKED '[{"name":"a","status":"COMPLETED","conclusion":"FAILURE"},
               {"name":"b","status":"IN_PROGRESS","conclusion":""}]' ""
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_running ]
}

# What is left once every self-clearing cause is named: approved, nothing running,
# nothing red, still blocked. Branch protection or a merge queue — a human moves it.
@test "terminal is a block with nothing pending and nothing red" {
  pr BLOCKED '[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]' APPROVED
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = terminal ]
}

# The sibling fetch already refuses this. Left to the forge it costs FAIL_MAX
# ticks and then reports the source as failing, whose documented remedy is
# checking auth — the one place the answer is not.
@test "a repo argument with no owner is refused, like the issue fetch" {
  run "$FETCH" notarepo 1
  [[ "$output" == *"reason=bad-args"* ]]
}

# The rollup is empty in the window between a push and the first check run, so
# counting it as "nothing pending" reads a wait as a permanent block.
@test "BLOCKED with an empty rollup is a wait, not a terminal block" {
  pr BLOCKED '[]' ""
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.cause')" = checks_expected ]
}

@test "BEHIND is named rather than collapsed into unknown" {
  pr BEHIND '[]'
  run "$FETCH" o/r 1
  [ "$(obj "$output" | jq -r '.merge.status')" = behind ]
  [ "$(obj "$output" | jq -r '.merge.cause')" = base_moved ]
}
