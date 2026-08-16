#!/usr/bin/env bats
#
# Tests for the one-call round packet. `gh` is stubbed on PATH and dispatches on
# the arguments, so the composition is exercised end to end — pr-round.sh's own
# fetches plus the pr-verdict.sh and pr-threads.sh calls it makes, which inherit
# the same stub.
#
# The packet's value is that it cannot be two-thirds performed, so most of what
# is pinned here is the contract that makes a partial answer legible: every
# source reports its own status, and an empty section with a failed status is not
# the same as an empty section with a healthy one.

ROUND="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/pr-round.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export FAIL_VERDICT="$BATS_TEST_TMPDIR/fail_verdict"
  export FAIL_REVIEWS="$BATS_TEST_TMPDIR/fail_reviews"
  export FAIL_INLINE="$BATS_TEST_TMPDIR/fail_inline"
  export FAIL_THREADS="$BATS_TEST_TMPDIR/fail_threads"
  export FAIL_DIFF="$BATS_TEST_TMPDIR/fail_diff"
  export VERDICT_JSON="$BATS_TEST_TMPDIR/verdict.json"
  export REVIEWS_JSON="$BATS_TEST_TMPDIR/reviews.json"
  export INLINE_JSON="$BATS_TEST_TMPDIR/inline.json"
  export THREADS_JSON="$BATS_TEST_TMPDIR/threads.json"
  export DIFF_TXT="$BATS_TEST_TMPDIR/diff.txt"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"

  # Dispatch by argument shape. `graphql` is matched before the inline-comments
  # pattern because pr-threads.sh's query names `pullRequest`, and ordering the
  # two the other way would serve it the comments fixture.
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$*" in
  *"--json headRefOid"*)       [ -f "$FAIL_VERDICT" ] && exit 1; cat "$VERDICT_JSON" ;;
  # The activity now arrives through fetch-pr-state.sh, which asks for the whole
  # tick and proves state/head/draft present. The fixtures stay about reviews and
  # comments; the envelope those tests do not care about is supplied here.
  *"--json state,isDraft"*)    [ -f "$FAIL_REVIEWS" ] && exit 1
                               jq -c '. + {state:"OPEN", isDraft:false, headRefOid:"bbb"}' \
                                 "$REVIEWS_JSON" 2>/dev/null || cat "$REVIEWS_JSON" ;;
  *graphql*)                   [ -f "$FAIL_THREADS" ] && exit 1; cat "$THREADS_JSON" ;;
  "pr diff"*|*compare*)        [ -f "$FAIL_DIFF" ]    && exit 1; cat "$DIFF_TXT" ;;
  *pulls/*comments*)           [ -f "$FAIL_INLINE" ]  && exit 1; cat "$INLINE_JSON" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"

  printf '{"headRefOid":"bbb","reviewDecision":"","reviews":[{"state":"APPROVED","commit":{"oid":"bbb"},"submittedAt":"2026-08-02T00:00:00Z"}],"commits":[{"oid":"bbb","committedDate":"2026-08-01T00:00:00Z"}]}' \
    > "$VERDICT_JSON"
  printf '{"reviews":[{"state":"CHANGES_REQUESTED","submittedAt":"2026-08-02T00:00:00Z","author":{"login":"human"},"body":"four things below"}],"comments":[]}' \
    > "$REVIEWS_JSON"
  printf '[{"created_at":"2026-08-02T00:00:00Z","user":{"login":"human"},"path":"a.sh","line":7,"id":99,"body":"the fourth thing"}]' \
    > "$INLINE_JSON"
  threads '[{"id":"PRRT_1","isResolved":false,"path":"a.sh","line":7,"comments":{"nodes":[{"author":{"login":"human"},"body":"still open"}]}}]'
  printf -- '--- a/a.sh\n+++ b/a.sh\n@@ -1 +1 @@\n-old\n+new\n' > "$DIFF_TXT"
}

threads() {  # <nodes-json>
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":%s}}}}}' "$1" \
    > "$THREADS_JSON"
}

result() { grep '^result=' <<<"$1"; }
field() { sed -n "s/.*[ ]$1=\([^ ]*\).*/\1/p" <<<"$2"; }

# Lines of one section, stopping at the next delimiter or the result line.
section() {  # <name> <output>
  awk -v n="── $1 ──" '$0 == n { inside = 1; next }
    /^── / || /^result=/ { inside = 0 } inside' <<<"$2"
}

# The headline claim: four parts, one invocation.
@test "one call returns the diff, the activity, the verdict and the threads" {
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$status" -eq 0 ]
  [[ "$(section diff "$output")" == *"+new"* ]]
  [ "$(section activity "$output" | wc -l | tr -d ' ')" = 2 ]
  [[ "$(section threads "$output")" == *PRRT_1* ]]
  local r; r=$(result "$output")
  [ "$(field verdict "$r")" = APPROVED ]
  [ "$(field at_head "$r")" = 1 ]
  [ "$(field activity "$r")" = 2 ]
  [ "$(field threads "$r")" = 1 ]
}

# Inline findings do not appear in `gh pr view --json reviews`, so a packet that
# dropped them would report a review body promising four findings with three
# visible — the failure git-workflow's "the review body is not the whole review"
# names, reproduced inside the consolidation meant to fix it.
@test "inline findings are in the packet alongside the review body" {
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [[ "$(section activity "$output")" == *'"kind":"review"'* ]]
  [[ "$(section activity "$output")" == *'"kind":"inline"'* ]]
}

# Replying in-thread needs the comment id as `in_reply_to`. Without it the caller
# fetches the same page again purely to learn a number the packet already read.
@test "an inline comment carries the id a reply needs" {
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [[ "$(section activity "$output")" == *'"id":99'* ]]
}

@test "activity older than the timestamp is not new activity" {
  run "$ROUND" o/r 1 aaa 2026-09-01T00:00:00Z me
  [ "$(field activity "$(result "$output")")" = 0 ]
  [ -z "$(section activity "$output")" ]
}

# The same self-exclusion watch-pr.sh's fifth argument buys. Without it the
# reviewer reads its own findings back as unread conversation.
@test "the caller's own activity is excluded, in both login spellings" {
  printf '{"reviews":[{"state":"COMMENTED","submittedAt":"2026-08-02T00:00:00Z","author":{"login":"agent-reviewer"},"body":"mine"}],"comments":[]}' \
    > "$REVIEWS_JSON"
  printf '[{"created_at":"2026-08-02T00:00:00Z","user":{"login":"agent-reviewer[bot]"},"path":"a.sh","line":7,"id":99,"body":"also mine"}]' \
    > "$INLINE_JSON"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z agent-reviewer
  [ "$(field activity "$(result "$output")")" = 0 ]
}

# THE RULE THE ISSUE'S WORDING WOULD HAVE INVERTED. git-workflow is explicit that
# the author must not narrow to the bot's threads — a human reviewer's thread
# blocks the merge just as surely — so the packet carries every unresolved one.
@test "threads are not narrowed to the bot's" {
  threads '[{"id":"PRRT_H","isResolved":false,"path":"a.sh","line":1,"comments":{"nodes":[{"author":{"login":"a-human"},"body":"blocking"}]}},
            {"id":"PRRT_B","isResolved":false,"path":"b.sh","line":2,"comments":{"nodes":[{"author":{"login":"agent-reviewer"},"body":"bot finding"}]}}]'
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z agent-reviewer
  [ "$(field threads "$(result "$output")")" = 2 ]
  [[ "$(section threads "$output")" == *PRRT_H* ]]
  [[ "$(section threads "$output")" == *PRRT_B* ]]
}

@test "a resolved thread is not outstanding work" {
  threads '[{"id":"PRRT_1","isResolved":true,"path":"a.sh","line":7,"comments":{"nodes":[{"author":{"login":"human"},"body":"done"}]}}]'
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field threads "$(result "$output")")" = 0 ]
}

# An ACTIVITY round: nobody pushed, so there is no delta and no request to make.
@test "a since-sha already at HEAD asks for no diff at all" {
  run "$ROUND" o/r 1 bbb 2026-08-01T00:00:00Z me
  [ "$(field diff "$(result "$output")")" = none ]
  [ -z "$(section diff "$output")" ]
  ! grep -q compare "$CALLS"
}

@test "an empty since-sha falls back to the full diff" {
  run "$ROUND" o/r 1 "" 2026-08-01T00:00:00Z me
  [ "$(field diff "$(result "$output")")" = full ]
  grep -q '^pr diff' "$CALLS"
}

@test "a since-sha behind HEAD asks for the delta, not the whole PR" {
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field diff "$(result "$output")")" = delta ]
  grep -q 'compare/aaa\.\.\.bbb' "$CALLS"
  ! grep -q '^pr diff' "$CALLS"
}

# The verdict is pr-verdict.sh's answer, not a second implementation of it. The
# reversed approval is the case a re-implementation gets wrong (it is the last
# APPROVED but not the last VERDICT), so seeing it come back CHANGES_REQUESTED is
# what proves the packet is really delegating.
@test "the verdict comes from pr-verdict.sh rather than a second copy of the rule" {
  printf '{"headRefOid":"bbb","reviewDecision":"","reviews":[{"state":"APPROVED","commit":{"oid":"bbb"}},{"state":"CHANGES_REQUESTED","commit":{"oid":"bbb"}}]}' \
    > "$VERDICT_JSON"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field verdict "$(result "$output")")" = CHANGES_REQUESTED ]
  [ "$(field at_head "$(result "$output")")" = 1 ]
}

# WITHOUT THIS THE FORCE-PUSH CHECK IS INERT ON THE PATH IT PROTECTS. pr-round.sh
# rebuilds its result line from an explicit list of fields rather than passing
# pr-verdict.sh's through, and git-workflow's clean-review path reads the packet
# rather than calling pr-verdict.sh itself — so a field the packet drops is one
# that path can never see.
@test "reviewed_after_head is forwarded onto the packet's result line" {
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field reviewed_after_head "$(result "$output")")" = 1 ]

  printf '{"headRefOid":"bbb","reviewDecision":"","reviews":[{"state":"APPROVED","commit":{"oid":"bbb"},"submittedAt":"2026-08-01T00:00:00Z"}],"commits":[{"oid":"bbb","committedDate":"2026-08-02T00:00:00Z"}]}' \
    > "$VERDICT_JSON"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field at_head "$(result "$output")")" = 1 ]
  [ "$(field reviewed_after_head "$(result "$output")")" = 0 ]
}

# A verdict source that failed knows nothing, and the callers gate the merge on
# this field reading 1 — so the default it falls back to must be `unknown`, never
# the `1` a previous healthy call would have produced.
@test "a failed verdict source yields unknown rather than a stale 1" {
  : > "$FAIL_VERDICT"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  local r; r=$(result "$output")
  [[ "$r" == result=OK* ]]
  [ "$(field verdict_src "$r")" = fail ]
  [ "$(field reviewed_after_head "$r")" = unknown ]
}

@test "an approval on a superseded commit is reported as not at head" {
  printf '{"headRefOid":"bbb","reviewDecision":"","reviews":[{"state":"APPROVED","commit":{"oid":"aaa"}}]}' \
    > "$VERDICT_JSON"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field at_head "$(result "$output")")" = 0 ]
  [ "$(field verdict_sha "$(result "$output")")" = aaa ]
}

# THE CONTRACT THAT MAKES A PARTIAL PACKET SAFE. Three parts are still a real
# answer, so the run reports OK — but the failed source is named, because an
# empty section is only "nothing there" where its status reads ok.
@test "a failed source is named while the rest of the packet still reports OK" {
  : > "$FAIL_THREADS"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  local r; r=$(result "$output")
  [[ "$r" == result=OK* ]]
  [ "$(field threads_src "$r")" = fail ]
  [ "$(field threads "$r")" = 0 ]
  [ "$(field reviews_src "$r")" = ok ]
  [ "$(field verdict "$r")" = APPROVED ]
}

@test "a failing inline fetch does not read as a review with no inline findings" {
  : > "$FAIL_INLINE"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field inline_src "$(result "$output")")" = fail ]
  [ "$(field reviews_src "$(result "$output")")" = ok ]
}

# A payload that came back and stopped parsing is a different fault from one that
# never came back, and only one of the two is worth retrying.
#
# Both halves come from one tick now, so a primary payload that stops parsing
# takes the inline findings with it even though their own request succeeded.
# That is a real loss against fetching the two separately, and it is the price of
# a tick being one object; what matters is that both sources SAY so rather than
# reporting an empty round.
@test "a payload that stops parsing reports shape on both halves, not fail" {
  printf 'not json at all' > "$REVIEWS_JSON"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field reviews_src "$(result "$output")")" = shape ]
  [ "$(field inline_src "$(result "$output")")" = shape ]
  [ "$(field activity "$(result "$output")")" = 0 ]
}

@test "an unreadable verdict does not silently become no verdict" {
  : > "$FAIL_VERDICT"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field verdict_src "$(result "$output")")" = fail ]
  [ "$(field verdict "$(result "$output")")" = NONE ]
}

# HEAD comes from the verdict call, so the delta has no second endpoint to
# resolve — reporting `fail` beats comparing against an empty SHA.
@test "a delta with no readable HEAD reports a failed diff, not an empty one" {
  : > "$FAIL_VERDICT"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field diff "$(result "$output")")" = fail ]
}

@test "a failing diff is named rather than read as an unchanged PR" {
  : > "$FAIL_DIFF"
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me
  [ "$(field diff "$(result "$output")")" = fail ]
  [ -z "$(section diff "$output")" ]
}

@test "missing arguments report bad-args rather than exiting silently" {
  run "$ROUND"
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$ROUND" o/r 1 aaa
  [ "$output" = "result=ERROR reason=bad-args" ]
}

@test "a repo with no slash is bad-args, not an API failure" {
  run "$ROUND" justarepo 1 aaa 2026-08-01T00:00:00Z me
  [ "$output" = "result=ERROR reason=bad-args" ]
}

# An empty slug matches no login, so nothing is excluded and the caller reads its
# own posts back as news. Refused for the reason watch-pr.sh refuses it.
@test "an empty slug is refused rather than defaulting to excluding nobody" {
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z ""
  [ "$output" = "result=ERROR reason=bad-args" ]
}

@test "a surplus argument reports bad-args" {
  run "$ROUND" o/r 1 aaa 2026-08-01T00:00:00Z me extra
  [ "$output" = "result=ERROR reason=bad-args" ]
}

# Every section header is present even when its section is empty, so a caller
# reading the packet by position never has to guess which one it is looking at.
@test "all three sections are delimited even when empty" {
  printf '{"reviews":[],"comments":[]}' > "$REVIEWS_JSON"
  printf '[]' > "$INLINE_JSON"
  threads '[]'
  run "$ROUND" o/r 1 bbb 2026-08-01T00:00:00Z me
  [[ "$output" == *"── diff ──"* ]]
  [[ "$output" == *"── activity ──"* ]]
  [[ "$output" == *"── threads ──"* ]]
  [ "$(result "$output" | wc -l | tr -d ' ')" = 1 ]
}
