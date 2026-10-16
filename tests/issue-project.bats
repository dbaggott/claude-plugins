#!/usr/bin/env bats
#
# Tests for the project lookup at pickup. `gh` is stubbed: it prints whatever
# JSON the test wrote, and exits 1 when the test asks it to, as real `gh` does on
# a GraphQL error.

LOOKUP="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/issue-project.sh"
P=https://github.com/o/other/issues/9

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

# <body> <parent-state|none> <children> -> the answer for one issue
answer() {
  jq -nc --arg b "$1" --arg s "$2" --argjson c "$3" --arg p "$P" '
    {data: {repository: {issue: {
      body: $b,
      parent: (if $s == "none" then null else {url: $p, state: $s} end),
      subIssues: {totalCount: $c}}}}}' > "$ANSWER"
}

@test "a plain issue has no parent and is not tracking" {
  answer "Fix the thing." none 0
  run "$LOOKUP" o/r 1
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK parent=none tracking=no children=0" ]
}

@test "a child names its open parent by URL, which may be in another repo" {
  answer "Part of the project." OPEN 0
  run "$LOOKUP" o/r 1
  [ "$output" = "result=OK parent=$P tracking=no children=0" ]
}

@test "a closed parent is none: its project is over" {
  answer "Left over." CLOSED 0
  run "$LOOKUP" o/r 1
  [ "$output" = "result=OK parent=none tracking=no children=0" ]
}

@test "the tracking marker makes a tracking issue before any child is filed" {
  answer 'This is a **tracking issue** for a notes export.' none 0
  run "$LOOKUP" o/r 1
  [ "$output" = "result=OK parent=none tracking=yes children=0" ]
}

@test "sub-issues make a tracking issue without the marker" {
  answer "An older parent." none 3
  run "$LOOKUP" o/r 1
  [ "$output" = "result=OK parent=none tracking=yes children=3" ]
}

@test "the marker counts only at the start of the body" {
  answer 'See https://x/1. This is a **tracking issue** quoted mid-body.' none 0
  run "$LOOKUP" o/r 1
  [ "$output" = "result=OK parent=none tracking=no children=0" ]
}

@test "an empty body is not an error" {
  jq -nc '{data: {repository: {issue: {body: null, parent: null, subIssues: {totalCount: 0}}}}}' > "$ANSWER"
  run "$LOOKUP" o/r 1
  [ "$output" = "result=OK parent=none tracking=no children=0" ]
}

@test "the number reaches GraphQL as an Int and the repo as a String" {
  answer "x" none 0
  run "$LOOKUP" o/2048 7
  grep -qx 'repo=2048' "$ARGV"
  grep -qx 'n=7' "$ARGV"
  grep -B1 -x 'n=7' "$ARGV" | grep -qx -- '-F'
}

@test "an unresolvable issue is not-found, even though gh exits 1" {
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND"}]}' > "$ANSWER"
  touch "$GQL_EXIT"
  run "$LOOKUP" o/r 1
  [ "$status" -eq 0 ]
  [[ "$output" == "result=ERROR reason=not-found now="* ]]
}

@test "an issue that answered beside an error is issue-query, not a missing parent" {
  echo '{"data":{"repository":{"issue":{"body":"x","parent":null,"subIssues":{"totalCount":0}}}},"errors":[{"type":"FORBIDDEN","path":["repository","issue","parent"]}]}' > "$ANSWER"
  touch "$GQL_EXIT"
  run "$LOOKUP" o/r 1
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
}

@test "no answer at all is issue-query" {
  touch "$GQL_EXIT"
  run "$LOOKUP" o/r 1
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
}

@test "a payload missing the sub-issue count is issue-query-shape" {
  echo '{"data":{"repository":{"issue":{"body":"x","parent":null}}}}' > "$ANSWER"
  run "$LOOKUP" o/r 1
  [[ "$output" == "result=ERROR reason=issue-query-shape now="* ]]
}

@test "bad arguments and another forge are refused before any call" {
  run "$LOOKUP" o/r
  [[ "$output" == "result=ERROR reason=bad-args now="* ]]
  run "$LOOKUP" r 1
  [[ "$output" == "result=ERROR reason=bad-args now="* ]]
  run "$LOOKUP" o/r 1x
  [[ "$output" == "result=ERROR reason=bad-args now="* ]]
  FORGE=gitlab run "$LOOKUP" o/r 1
  [[ "$output" == "result=ERROR reason=unsupported-forge now="* ]]
  [ ! -s "$ARGV" ]
}
