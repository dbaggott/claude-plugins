#!/usr/bin/env bats
#
# Tests for the read of the open issues one issue blocks. `gh` is stubbed: it
# prints whatever JSON the test wrote, and exits 1 when the test asks it to, as
# real `gh` does on a GraphQL error.

BLOCKING="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/issue-blocking.sh"
U=https://github.com/o/r/issues

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export ANSWER="$BATS_TEST_TMPDIR/answer.json"; : > "$ANSWER"
  export ARGV="$BATS_TEST_TMPDIR/argv"; : > "$ARGV"
  export GQL_EXIT="$BATS_TEST_TMPDIR/gql_exit"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$ARGV"
cat "$ANSWER"
[ -f "$GQL_EXIT" ] && exit 1
exit 0
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

# [<n>:<state>...] -> the answer for an issue blocking each, totalCount the
# number given, or $TOTAL when set.
answer() {
  printf '%s\n' "$@" | jq -Rcs --arg u "$U" --argjson t "${TOTAL:-null}" '
    [ split("\n")[] | select(. != "") | split(":") | {url: "\($u)/\(.[0])", state: .[1]} ]
    | {data: {repository: {issue: {blocking: {totalCount: ($t // length), nodes: .}}}}}' > "$ANSWER"
}

@test "an issue blocking nothing is a complete, empty answer" {
  answer
  run "$BLOCKING" o/r 1
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK count=0" ]
}

@test "a page of blocked issues prints each URL, then the count" {
  answer 2:OPEN 3:OPEN
  run "$BLOCKING" o/r 1
  [ "$output" = "$(printf '%s\n' "$U/2" "$U/3" "result=OK count=2")" ]
}

@test "a closed blocked issue is left out of the list and the count" {
  answer 2:OPEN 3:CLOSED
  run "$BLOCKING" o/r 1
  [ "$output" = "$(printf '%s\n' "$U/2" "result=OK count=1")" ]
}

@test "a page shorter than its total is set-overflow, with no URLs" {
  TOTAL=51 answer 2:OPEN
  run "$BLOCKING" o/r 1
  [ "$output" = "result=ERROR reason=set-overflow" ]
}

@test "an unresolvable issue is not-found, even though gh exits 1" {
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND"}]}' > "$ANSWER"
  touch "$GQL_EXIT"
  run "$BLOCKING" o/r 1
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=not-found" ]
}

@test "no answer, or a null issue with another error, is issue-query" {
  touch "$GQL_EXIT"
  run "$BLOCKING" o/r 1
  [ "$output" = "result=ERROR reason=issue-query" ]
  rm "$GQL_EXIT"
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"FORBIDDEN"}]}' > "$ANSWER"
  run "$BLOCKING" o/r 1
  [ "$output" = "result=ERROR reason=issue-query" ]
}

@test "a payload that stops parsing, or a null node, is issue-query-shape" {
  echo 'not json' > "$ANSWER"
  run "$BLOCKING" o/r 1
  [ "$output" = "result=ERROR reason=issue-query-shape" ]
  echo '{"data":{"repository":{"issue":{"blocking":{"totalCount":1,"nodes":[null]}}}}}' > "$ANSWER"
  run "$BLOCKING" o/r 1
  [ "$output" = "result=ERROR reason=issue-query-shape" ]
  echo '{"data":{"repository":{"issue":{"blocking":null}}}}' > "$ANSWER"
  run "$BLOCKING" o/r 1
  [ "$output" = "result=ERROR reason=issue-query-shape" ]
}

@test "bad arguments are refused before any query" {
  local args
  for args in "" "o/r" "o 1" "o/r/x 1" "/r 1" "o/ 1" "o/r 1x" "o/r 1 2"; do
    # shellcheck disable=SC2086  # each case is a deliberately split argument list
    run "$BLOCKING" $args
    [ "$output" = "result=ERROR reason=bad-args" ] || { echo "'$args': $output"; false; }
  done
  [ ! -s "$ARGV" ]
}

@test "another forge is refused before any query" {
  FORGE=gitlab run "$BLOCKING" o/r 1
  [ "$output" = "result=ERROR reason=unsupported-forge" ]
  [ ! -s "$ARGV" ]
}

@test "the repo and number reach GraphQL as a String and an Int" {
  answer
  run "$BLOCKING" 0wner/123 7
  grep -qx 'owner=0wner' "$ARGV"
  grep -qx 'repo=123' "$ARGV"
  grep -qx 'n=7' "$ARGV"
  grep -B1 -x 'repo=123' "$ARGV" | grep -qx -- '-f'
  grep -B1 -x 'n=7' "$ARGV" | grep -qx -- '-F'
}
