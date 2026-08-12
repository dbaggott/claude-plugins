#!/usr/bin/env bats
#
# Tests for issue->PR discovery. `gh` is stubbed on PATH and told apart by
# subcommand and path, so each of the three sources can be failed independently —
# which is the only way to exercise the partial-failure contract this script
# exists to make legible.
#
# The union used to live as a fenced block in two skills plus a third variant
# inside watch-pr.sh, kept in step by a coupling test that could only prove the
# copies MENTIONED the same endpoints, never that they behaved alike. These are
# the behaviours that were never checked.

SOURCES="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/pr-sources.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export CLOSING="$BATS_TEST_TMPDIR/closing"; echo '[]' > "$CLOSING"
  export XREF="$BATS_TEST_TMPDIR/xref";       echo '[[]]' > "$XREF"
  export SEARCH="$BATS_TEST_TMPDIR/search";   echo '[]' > "$SEARCH"
  export FAIL_CLOSING="$BATS_TEST_TMPDIR/fail_closing"
  export FAIL_TIMELINE="$BATS_TEST_TMPDIR/fail_timeline"
  export FAIL_SEARCH="$BATS_TEST_TMPDIR/fail_search"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$1 $2" in
  "issue view")
    [ -f "$FAIL_CLOSING" ] && exit 1
    printf '{"closedByPullRequestsReferences":%s}' "$(cat "$CLOSING")" ;;
  "search prs")
    [ -f "$FAIL_SEARCH" ] && exit 1
    cat "$SEARCH" ;;
  "api "*|"api")
    [ -f "$FAIL_TIMELINE" ] && exit 1
    # `--slurp` shape: an array OF PAGES. The stub emits it because that is what
    # the script parses (`.[][]`); a flat array here would let a `.[]`
    # regression pass.
    cat "$XREF" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

urls_of()  { grep -v '^result=' <<<"$1" || true; }
result_of() { grep '^result=' <<<"$1"; }

xref() {  # <url> [more...]
  local out="" u
  for u in "$@"; do
    out="$out{\"event\":\"cross-referenced\",\"source\":{\"issue\":{\"pull_request\":{},\"html_url\":\"$u\"}}},"
  done
  echo "[[${out%,}]]" > "$XREF"
}

@test "the three sources are unioned and deduped" {
  echo '[{"url":"https://x/pull/1"}]' > "$CLOSING"
  xref https://x/pull/1 https://x/pull/2
  echo '[{"url":"https://x/pull/3"}]' > "$SEARCH"
  run "$SOURCES" o/r 5
  [ "$status" -eq 0 ]
  [ "$(urls_of "$output" | wc -l | tr -d ' ')" = 3 ]
  [[ "$output" == *"result=OK count=3"* ]]
}

# THE SHAPE `git-workflow`'s MULTI-REPO RULE PRODUCES: exactly one sibling
# carries the closing keyword and the rest merely mention the issue. A site
# polling only the closing source sees one PR of a set and believes it is whole.
@test "a mention-only sibling is found even though it closes nothing" {
  xref https://x/pull/7
  run "$SOURCES" o/r 5
  [ "$(urls_of "$output")" = "https://x/pull/7" ]
}

# A cross-reference to a plain ISSUE has no `pull_request` member. Counting it
# would report an issue URL as a resolving PR.
@test "a cross-referenced issue is not mistaken for a PR" {
  echo '[[{"event":"cross-referenced","source":{"issue":{"html_url":"https://x/issues/9"}}}]]' > "$XREF"
  run "$SOURCES" o/r 5
  [ "$(urls_of "$output")" = "" ]
  [[ "$output" == *"count=0"* ]]
}

# Deduping across PAGES, not within one. `gh --jq` applies per page, so a jq-side
# `unique` would pass a single-page test and still emit duplicates on a busy
# issue — which is exactly where the timeline source matters most.
@test "duplicates spanning two timeline pages are deduped" {
  local e='{"event":"cross-referenced","source":{"issue":{"pull_request":{},"html_url":"https://x/pull/4"}}}'
  echo "[[$e],[$e]]" > "$XREF"
  run "$SOURCES" o/r 5
  [ "$(urls_of "$output" | wc -l | tr -d ' ')" = 1 ]
}

@test "the search is scoped to the owner, never the repo" {
  run "$SOURCES" acme/api 5
  grep -q 'search prs --owner acme' "$CALLS"
  ! grep -q 'search prs.*--repo' "$CALLS"
}

# A union with one dead source is still a real answer, so it must be reported
# rather than suppressed — but the failure has to be named, or "nothing found"
# and "nothing found by what worked" become the same output.
@test "one dead source still answers, and says which one died" {
  : > "$FAIL_TIMELINE"
  echo '[{"url":"https://x/pull/1"}]' > "$CLOSING"
  run "$SOURCES" o/r 5
  [ "$status" -eq 0 ]
  [ "$(urls_of "$output")" = "https://x/pull/1" ]
  [[ "$output" == *"timeline=fail"* ]]
  [[ "$output" == *"closing=ok"* ]]
}

@test "a timeline that stops parsing is a shape failure, not an empty result" {
  echo 'not json' > "$XREF"
  run "$SOURCES" o/r 5
  [[ "$output" == *"timeline=shape"* ]]
  [[ "$output" == *"result=OK"* ]]
}

# ONE VOCABULARY ACROSS ALL THREE SOURCES. `closing` once reported a parse
# failure as `fail` while the other two reported `shape`, so the same condition
# had two names in the one file whose job is making partial failure legible — and
# a caller matching a per-source enumeration would not recognise the third value.
@test "a parse failure is spelled shape whichever source it happens in" {
  echo 'not json' > "$CLOSING"
  run "$SOURCES" o/r 5
  [[ "$output" == *"closing=shape"* ]]
  echo 'not json' > "$SEARCH"
  run "$SOURCES" o/r 5
  [[ "$output" == *"search=shape"* ]]
}

@test "a request that never comes back is spelled fail, whichever source it is" {
  : > "$FAIL_CLOSING"
  run "$SOURCES" o/r 5
  [[ "$output" == *"closing=fail"* ]]

  rm -f "$FAIL_CLOSING"; : > "$FAIL_TIMELINE"
  run "$SOURCES" o/r 5
  [[ "$output" == *"timeline=fail"* ]]

  rm -f "$FAIL_TIMELINE"; : > "$FAIL_SEARCH"
  run "$SOURCES" o/r 5
  [[ "$output" == *"search=fail"* ]]
}

# All three blind is the one case where an empty list would be an outright lie,
# so it is an ERROR rather than `count=0`.
@test "every source failing is an error, not an empty set" {
  : > "$FAIL_CLOSING"; : > "$FAIL_TIMELINE"; : > "$FAIL_SEARCH"
  run "$SOURCES" o/r 5
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=all-sources" ]
}

@test "a genuinely unlinked issue reports count=0 with every source healthy" {
  run "$SOURCES" o/r 5
  [ "$output" = "result=OK count=0 closing=ok search=ok timeline=ok" ]
}

@test "missing or malformed arguments report bad-args" {
  run "$SOURCES"
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$SOURCES" o/r
  [ "$output" = "result=ERROR reason=bad-args" ]
  # No slash: the owner cannot be derived, so the search would be scoped wrong.
  run "$SOURCES" justarepo 5
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$SOURCES" o/r 5 extra
  [ "$output" = "result=ERROR reason=bad-args" ]
}

@test "bad arguments query nothing at all" {
  run "$SOURCES" justarepo 5
  [ ! -s "$CALLS" ]
}
