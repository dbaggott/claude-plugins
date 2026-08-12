#!/usr/bin/env bats
#
# Tests for the standing-verdict check. `gh` is stubbed on PATH and serves
# whatever JSON the test writes to $STATEFILE, so every branch is reachable
# without a network or a real PR.
#
# This check used to be a fenced block duplicated in two skills, where shellcheck
# couldn't see it and nothing could test it. The cases below are the ones the
# prose copies documented in words and nothing verified — most of all the
# reversed approval, which the first cut of that block got wrong in both copies
# at once.

VERDICT="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/pr-verdict.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export STATEFILE="$BATS_TEST_TMPDIR/state"
  export FAIL_GH="$BATS_TEST_TMPDIR/fail_gh"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
[ -f "$FAIL_GH" ] && exit 1
cat "$STATEFILE"
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

# headRefOid, then a JSON array of {state, oid} pairs in submission order.
pr_reviews() {
  local head="$1"; shift
  printf '{"headRefOid":"%s","reviewDecision":"","reviews":%s}' "$head" "$1" > "$STATEFILE"
}

field() { sed -n "s/.*[ ]$1=\([^ ]*\).*/\1/p" <<<"$2"; }

@test "an approval on the current head reports at_head=1" {
  pr_reviews aaa '[{"state":"APPROVED","commit":{"oid":"aaa"}}]'
  run "$VERDICT" o/r 1
  [ "$status" -eq 0 ]
  [[ "$output" == result=OK* ]]
  [ "$(field verdict "$output")" = APPROVED ]
  [ "$(field at_head "$output")" = 1 ]
}

@test "an approval on a superseded commit reports at_head=0" {
  pr_reviews bbb '[{"state":"APPROVED","commit":{"oid":"aaa"}}]'
  run "$VERDICT" o/r 1
  [ "$(field verdict "$output")" = APPROVED ]
  [ "$(field at_head "$output")" = 0 ]
  [ "$(field verdict_sha "$output")" = aaa ]
}

# THE REGRESSION THE PROSE COPIES CARRIED. Filtering to APPROVED and taking the
# last one reads this as approved, because the approval is the last APPROVED in
# the list. It is not the last VERDICT.
@test "an approval reversed at the same SHA is not an approval" {
  pr_reviews aaa '[{"state":"APPROVED","commit":{"oid":"aaa"}},
                   {"state":"CHANGES_REQUESTED","commit":{"oid":"aaa"}}]'
  run "$VERDICT" o/r 1
  [ "$(field verdict "$output")" = CHANGES_REQUESTED ]
  [ "$(field at_head "$output")" = 1 ]
}

# The other half of the same rule, and the reason COMMENTED is excluded rather
# than merely unmentioned: a reviewer answering a thread posts one, so counting
# it would blank the verdict on every exchange.
@test "a COMMENTED review does not displace the standing verdict" {
  pr_reviews aaa '[{"state":"APPROVED","commit":{"oid":"aaa"}},
                   {"state":"COMMENTED","commit":{"oid":"aaa"}}]'
  run "$VERDICT" o/r 1
  [ "$(field verdict "$output")" = APPROVED ]
  [ "$(field at_head "$output")" = 1 ]
}

@test "a dismissal ends the review it dismissed" {
  pr_reviews aaa '[{"state":"APPROVED","commit":{"oid":"aaa"}},
                   {"state":"DISMISSED","commit":{"oid":"aaa"}}]'
  run "$VERDICT" o/r 1
  [ "$(field verdict "$output")" = DISMISSED ]
}

@test "a PR with no reviews reports NONE rather than failing" {
  pr_reviews aaa '[]'
  run "$VERDICT" o/r 1
  [ "$status" -eq 0 ]
  [ "$(field verdict "$output")" = NONE ]
  [ "$(field at_head "$output")" = 0 ]
}

# at_head must not be 1 just because both sides are empty — that would report an
# absent verdict as attached to the head.
@test "an empty verdict SHA never counts as attached to head" {
  pr_reviews aaa '[{"state":"APPROVED"}]'
  run "$VERDICT" o/r 1
  [ "$(field at_head "$output")" = 0 ]
}

@test "reviewDecision is passed through so a caller can tell the two regimes apart" {
  printf '{"headRefOid":"aaa","reviewDecision":"APPROVED","reviews":[]}' > "$STATEFILE"
  run "$VERDICT" o/r 1
  [[ "$output" == *"review_decision=APPROVED"* ]]
}

@test "an unreachable gh reports pr-view, not a wrong answer" {
  : > "$FAIL_GH"
  run "$VERDICT" o/r 1
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=pr-view" ]
}

# A well-formed JSON error body parses fine, so `// empty` alone would let it
# through with an empty head and every comparison silently false. The same gate
# watch-pr.sh applies to `.state`.
@test "a well-formed error body is caught as a shape failure" {
  printf '{"message":"Not Found"}' > "$STATEFILE"
  run "$VERDICT" o/r 1
  [ "$output" = "result=ERROR reason=pr-view-shape" ]
}

@test "a payload that stops parsing reports pr-view-shape" {
  printf 'not json at all' > "$STATEFILE"
  run "$VERDICT" o/r 1
  [ "$output" = "result=ERROR reason=pr-view-shape" ]
}

@test "missing arguments report bad-args rather than exiting silently" {
  run "$VERDICT"
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$VERDICT" o/r
  [ "$output" = "result=ERROR reason=bad-args" ]
}

# Nothing here splits on the slash — `--repo` is handed to gh whole — so a
# malformed repo would otherwise reach the API and come back as `pr-view`. Both
# calling skills gloss that as "the check could not see", which sends the caller
# to `gh auth status` when the fix is the argument they typed.
@test "a repo with no slash is bad-args, not an API failure" {
  pr_reviews aaa '[]'
  run "$VERDICT" justarepo 1
  [ "$output" = "result=ERROR reason=bad-args" ]
}

# A caller branches on `result=`, so a surplus argument must not be swallowed
# into a plausible-looking answer.
@test "a surplus argument reports bad-args" {
  pr_reviews aaa '[]'
  run "$VERDICT" o/r 1 extra
  [ "$output" = "result=ERROR reason=bad-args" ]
}
