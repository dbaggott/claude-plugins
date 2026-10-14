#!/usr/bin/env bats
#
# Tests for the tracking-issue set snapshot. `gh` is stubbed: it prints whatever
# JSON the test wrote, and exits 1 when the test asks it to, as real `gh` does on a
# GraphQL error.

FETCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/fetch-issue-set.sh"
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

issue() {  # <n> <state> <lastEditedAt|null> [blocker-n...] -> one issue node
  local n="$1" state="$2" edited="$3"; shift 3
  printf '%s\n' "$@" | jq -cs --argjson n "$n" --arg s "$state" --arg e "$edited" --arg u "$U" '
    map(select(. != "")) as $b
    | {url: "\($u)/\($n)", number: $n, title: "t\($n)", body: "body \($n)", state: $s,
       createdAt: "2026-10-01T00:00:00Z",
       lastEditedAt: (if $e == "null" then null else $e end),
       blockedBy: {totalCount: ($b | length), nodes: ($b | map({url: "\($u)/\(.)"}))}}'
}
# <total> [child-node...] -> the answer for parent 1
answer() {
  local total="$1"; shift
  printf '%s\n' "$@" | jq -cs --argjson t "$total" --arg u "$U" '
    {data: {repository: {issue: {
      url: "\($u)/1", number: 1, title: "parent", body: "design", state: "OPEN",
      createdAt: "2026-10-01T00:00:00Z", lastEditedAt: "2026-10-02T00:00:00Z",
      subIssues: {totalCount: $t, nodes: map(select(. != null))}}}}}' > "$ANSWER"
}
object() { head -1 <<<"$1"; }
line() { tail -1 <<<"$1"; }

@test "the parent and every child arrive as one object, with blockers as URLs" {
  answer 2 "$(issue 2 OPEN 2026-10-03T00:00:00Z)" "$(issue 3 CLOSED null 2)"
  run "$FETCH" o/r 1
  [ "$status" -eq 0 ]
  [[ "$(line "$output")" =~ ^result=OK\ now=[0-9T:Z-]+\ children=2$ ]]
  [ "$(object "$output" | jq -c '.parent | {number, body, body_edited}')" \
    = '{"number":1,"body":"design","body_edited":"2026-10-02T00:00:00Z"}' ]
  [ "$(object "$output" | jq -c '[.children[] | {number, state, blocked_by}]')" \
    = "[{\"number\":2,\"state\":\"OPEN\",\"blocked_by\":[]},{\"number\":3,\"state\":\"CLOSED\",\"blocked_by\":[\"$U/2\"]}]" ]
}

@test "a never-edited body is a null body_edited, with created for its age" {
  answer 1 "$(issue 2 OPEN null)"
  run "$FETCH" o/r 1
  [ "$(object "$output" | jq -c '.children[0] | [.body_edited, .created]')" \
    = '[null,"2026-10-01T00:00:00Z"]' ]
}

@test "the output carries no GitHub field names" {
  answer 1 "$(issue 2 OPEN null 3)"
  run "$FETCH" o/r 1
  [ "$(object "$output" | jq -c '[paths | map(strings) | .[]] | unique')" \
    = '["blocked_by","body","body_edited","children","created","number","parent","state","title","url"]' ]
}

@test "a parent with no sub-issues is an empty set, not an error" {
  answer 0
  run "$FETCH" o/r 1
  [[ "$(line "$output")" == result=OK*children=0 ]]
  [ "$(object "$output" | jq -c .children)" = '[]' ]
}

@test "fewer sub-issues than the total is set-overflow, not a smaller set" {
  answer 3 "$(issue 2 OPEN null)"
  run "$FETCH" o/r 1
  [[ "$(line "$output")" == "result=ERROR reason=set-overflow now="* ]]
  [ "$(wc -l <<<"$output")" -eq 1 ]
}

@test "one child with more blockers than returned is set-overflow" {
  answer 1 "$(issue 2 OPEN null 3 | jq -c '.blockedBy.totalCount = 60')"
  run "$FETCH" o/r 1
  [[ "$(line "$output")" == "result=ERROR reason=set-overflow now="* ]]
}

@test "an unresolvable issue is not-found, even though gh exits 1" {
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND"}]}' > "$ANSWER"
  touch "$GQL_EXIT"
  run "$FETCH" o/r 1
  [ "$status" -eq 0 ]
  [[ "$output" == "result=ERROR reason=not-found now="* ]]
}

@test "no answer at all is issue-query" {
  touch "$GQL_EXIT"
  run "$FETCH" o/r 1
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
}

@test "a null issue with no NOT_FOUND error is issue-query" {
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"FORBIDDEN"}]}' > "$ANSWER"
  run "$FETCH" o/r 1
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
}

@test "a payload that stops parsing is issue-query-shape, not set-overflow" {
  echo '{"data":{"repository":{"issue":{"number":1,"subIssues":{"totalCount":1}}}}}' > "$ANSWER"
  run "$FETCH" o/r 1
  [[ "$output" == "result=ERROR reason=issue-query-shape now="* ]]
  echo 'not json' > "$ANSWER"
  run "$FETCH" o/r 1
  [[ "$output" == "result=ERROR reason=issue-query-shape now="* ]]
}

@test "owner and repo bind as strings and the number as an Int" {
  answer 0
  run "$FETCH" 2048/1999 7
  grep -qx 'owner=2048' "$ARGV"
  grep -qx 'repo=1999' "$ARGV"
  grep -qx 'n=7' "$ARGV"
  [ "$(grep -B1 -x 'owner=2048' "$ARGV" | head -1)" = -f ]
  [ "$(grep -B1 -x 'n=7' "$ARGV" | head -1)" = -F ]
}

@test "bad arguments are refused before any query" {
  local args
  for args in "" "o/r" "o/r 1 2" "or 1" "o/r/x 1" "o/r abc" "/r 1" "o/ 1"; do
    # shellcheck disable=SC2086  # word splitting is the point
    run "$FETCH" $args
    [[ "$output" == "result=ERROR reason=bad-args now="* ]] || { echo "accepted: '$args'"; false; }
  done
  [ ! -s "$ARGV" ]
}

@test "another forge is refused before any query" {
  FORGE=gitlab run "$FETCH" o/r 1
  [[ "$output" == "result=ERROR reason=unsupported-forge now="* ]]
  [ ! -s "$ARGV" ]
}
