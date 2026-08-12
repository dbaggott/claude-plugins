#!/usr/bin/env bats
#
# Tests for the review-thread list/resolve helper. `gh` is stubbed on PATH and
# tells a query from a mutation by the GraphQL text it is handed, so listing and
# resolving are exercised independently without a network.
#
# This was the largest fenced block in the marketplace, duplicated across two
# skills, carrying two quirks that are silent when wrong: GraphQL reports a Bot
# author's login WITHOUT the `[bot]` suffix, and an empty slug matches nothing
# while looking like "no outstanding findings".

THREADS="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/pr-threads.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export NODES="$BATS_TEST_TMPDIR/nodes"; echo '[]' > "$NODES"
  export FAIL_QUERY="$BATS_TEST_TMPDIR/fail_query"
  export FAIL_MUTATION="$BATS_TEST_TMPDIR/fail_mutation"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$*" in
  *resolveReviewThread*)
    [ -f "$FAIL_MUTATION" ] && exit 1
    echo '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}' ;;
  *reviewThreads*)
    [ -f "$FAIL_QUERY" ] && exit 1
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":%s}}}}}' "$(cat "$NODES")" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"

  # A reviewer config the script can read, so --mine has a slug by default. The
  # no-slug case points DNBG_REVIEWER_CONFIG_DIR somewhere empty instead.
  export DNBG_REVIEWER_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$DNBG_REVIEWER_CONFIG_DIR"
  echo '{"slug":"agent-reviewer-me"}' > "$DNBG_REVIEWER_CONFIG_DIR/config.json"
}

# id, isResolved, author — enough to drive both filters.
node() {
  printf '{"id":"%s","isResolved":%s,"path":"a.go","line":4,"comments":{"nodes":[{"author":{"login":"%s"},"body":"finding"}]}}' \
    "$1" "$2" "$3"
}
nodes() { local IFS=,; echo "[$*]" > "$NODES"; }

jsonl_of() { grep -v '^result=' <<<"$1" || true; }

@test "listing returns unresolved threads as one JSON object per line" {
  nodes "$(node T1 false alice)" "$(node T2 false bob)"
  run "$THREADS" o/r 1
  [ "$status" -eq 0 ]
  [ "$(jsonl_of "$output" | wc -l | tr -d ' ')" = 2 ]
  [[ "$output" == *"result=OK count=2"* ]]
  # Each line must stand alone as JSON — that is the whole point of JSONL.
  jsonl_of "$output" | while read -r l; do jq -e . >/dev/null <<<"$l"; done
}

@test "resolved threads are excluded" {
  nodes "$(node T1 true alice)" "$(node T2 false bob)"
  run "$THREADS" o/r 1
  [[ "$output" == *"count=1"* ]]
  [[ "$output" == *'"id":"T2"'* ]]
}

@test "the payload carries path, line, author and body" {
  nodes "$(node T1 false alice)"
  run "$THREADS" o/r 1
  line=$(jsonl_of "$output")
  [ "$(jq -r .path <<<"$line")" = a.go ]
  [ "$(jq -r .line <<<"$line")" = 4 ]
  [ "$(jq -r .author <<<"$line")" = alice ]
  [ "$(jq -r .body <<<"$line")" = finding ]
}

# THE QUIRK THE PROSE COPIES DOCUMENTED IN WORDS. GraphQL reports a Bot author's
# login without the `[bot]` suffix, so matching the suffixed form never hits and
# --mine silently returns nothing.
@test "--mine matches the App slug as GraphQL actually reports it" {
  nodes "$(node T1 false agent-reviewer-me)" "$(node T2 false alice)"
  run "$THREADS" o/r 1 --mine
  [[ "$output" == *"count=1"* ]]
  [[ "$output" == *'"id":"T1"'* ]]
}

@test "--mine also accepts the suffixed spelling" {
  nodes "$(node T1 false 'agent-reviewer-me[bot]')"
  run "$THREADS" o/r 1 --mine
  [[ "$output" == *"count=1"* ]]
}

# Without --mine the author is irrelevant: a human reviewer's thread blocks the
# merge just as surely, so an author enumerating outstanding work must see it.
@test "without --mine every unresolved thread is listed regardless of author" {
  nodes "$(node T1 false agent-reviewer-me)" "$(node T2 false a-human)"
  run "$THREADS" o/r 1
  [[ "$output" == *"count=2"* ]]
}

# An empty match string selects nothing, which reads as "no outstanding
# findings" — the silent blindness the guard exists for.
@test "--mine with no configured slug bails instead of matching nothing" {
  export DNBG_REVIEWER_CONFIG_DIR="$BATS_TEST_TMPDIR/empty"
  nodes "$(node T1 false agent-reviewer-me)"
  run "$THREADS" o/r 1 --mine
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=no-slug" ]
}

@test "a config present but carrying no slug is the same bail" {
  echo '{}' > "$DNBG_REVIEWER_CONFIG_DIR/config.json"
  run "$THREADS" o/r 1 --mine
  [ "$output" = "result=ERROR reason=no-slug" ]
}

@test "the no-slug bail queries nothing" {
  echo '{}' > "$DNBG_REVIEWER_CONFIG_DIR/config.json"
  run "$THREADS" o/r 1 --mine
  [ ! -s "$CALLS" ]
}

@test "--resolve issues the mutation and confirms the thread id" {
  run "$THREADS" o/r 1 --resolve PRRT_abc
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK resolved=PRRT_abc" ]
  grep -q 'resolveReviewThread' "$CALLS"
}

@test "a failed mutation reports resolve rather than success" {
  : > "$FAIL_MUTATION"
  run "$THREADS" o/r 1 --resolve PRRT_abc
  [ "$output" = "result=ERROR reason=resolve" ]
}

@test "an unreachable graphql reports graphql, not an empty thread list" {
  : > "$FAIL_QUERY"
  run "$THREADS" o/r 1
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=graphql" ]
}

@test "a payload that stops parsing reports graphql-shape" {
  echo 'not json' > "$NODES"
  run "$THREADS" o/r 1
  [ "$output" = "result=ERROR reason=graphql-shape" ]
}

@test "a PR with no threads reports count=0" {
  run "$THREADS" o/r 1
  [ "$output" = "result=OK count=0" ]
}

@test "missing or malformed arguments report bad-args" {
  run "$THREADS"
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$THREADS" o/r
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$THREADS" justarepo 1
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$THREADS" o/r 1 --bogus
  [ "$output" = "result=ERROR reason=bad-args" ]
}

# A valueless --resolve once spun the argument loop forever, because the branch
# fell through to a `shift 2` that could not advance a one-element argv. A hang
# is the one failure a caller reading `result=` lines cannot diagnose at all, so
# the guard is worth a test that would itself hang without it.
#
# `perl -e 'alarm'` rather than `timeout(1)`: coreutils is not on stock macOS, so
# `timeout` exits 127 there and the test passes for the wrong reason — a check
# against hanging that silently stops checking is worse than none. The alarm
# survives the `exec` per POSIX, and lands as status 142 (SIGALRM).
@test "a valueless --resolve reports bad-args instead of hanging" {
  run perl -e 'alarm shift; exec @ARGV' 10 "$THREADS" o/r 1 --resolve
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=bad-args" ]
}

# They are different operations, and which one was meant is not recoverable from
# the pair — so the pair is refused rather than one silently winning.
@test "--mine and --resolve together are refused" {
  run "$THREADS" o/r 1 --mine --resolve PRRT_abc
  [ "$output" = "result=ERROR reason=bad-args" ]
  [ ! -s "$CALLS" ]
}
