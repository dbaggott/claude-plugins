#!/usr/bin/env bats
#
# Tests for the tracking issue's ready set. `gh` is stubbed: it prints whatever
# JSON the test wrote, and exits 1 when the test asks it to, as real `gh` does on a
# GraphQL error.

READY="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/ready-set.sh"
U=https://github.com/o/r/issues
BOT=rev-bot

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

# <n> [state] -> an open, unclaimed, unblocked child with no comments. Tests
# shape the rest with jq, through the helpers below.
child() {
  jq -cn --argjson n "$1" --arg s "${2:-OPEN}" --arg u "$U" '
    {url: "\($u)/\($n)", number: $n, title: "t\($n)", state: $s,
     assignees: {totalCount: 0, nodes: []}, labels: {totalCount: 0, nodes: []},
     blockedBy: {totalCount: 0, nodes: []}, comments: {nodes: []}}'
}
blocked_by() {  # <node> <n> <state> -> the node with one more blocker
  jq -c --argjson n "$2" --arg s "$3" --arg u "$U" '
    .blockedBy.nodes += [{url: "\($u)/\($n)", state: $s}]
    | .blockedBy.totalCount += 1' <<<"$1"
}
comment() {  # <node> <login> <body> -> the node with one more comment, newest last
  jq -c --arg l "$2" --arg b "$3" '.comments.nodes += [{author: {login: $l}, body: $b}]' <<<"$1"
}
# [child-node...] -> the answer for parent 1, whose comments come from $PARENT_COMMENTS
answer() {
  printf '%s\n' "$@" | jq -cs --arg u "$U" --argjson pc "${PARENT_COMMENTS:-[]}" '
    {data: {repository: {issue: {
      url: "\($u)/1", number: 1, comments: {nodes: $pc},
      subIssues: {totalCount: length, nodes: .}}}}}' > "$ANSWER"
}
spec_reviewed() {  # the parent carries a design review verdict from the bot
  PARENT_COMMENTS=$(jq -cn --arg l "${BOT}[bot]" \
    '[{author: {login: $l}, body: "**Spec review (design mode), round 1: READY**\n\nbody"}]')
}
object() { head -1 <<<"$1"; }
line() { tail -1 <<<"$1"; }
numbers() { object "$1" | jq -c "[.$2[].number]"; }

@test "an open, unclaimed, unblocked child is ready; a closed one is in neither list" {
  answer "$(child 2)" "$(child 3 CLOSED)"
  run "$READY" o/r 1 --slug=$BOT
  [ "$status" -eq 0 ]
  [[ "$(line "$output")" =~ ^result=OK\ now=[0-9T:Z-]+\ children=2\ open=1\ ready=1$ ]]
  [ "$(object "$output" | jq -c '.ready')" = "[{\"url\":\"$U/2\",\"number\":2,\"title\":\"t2\"}]" ]
  [ "$(numbers "$output" waiting)" = '[]' ]
  [ "$(object "$output" | jq -c .parent)" = "{\"url\":\"$U/1\",\"number\":1,\"spec_review\":false}" ]
}

@test "a closed blocker does not hold a child; an open one does, and is named" {
  answer "$(blocked_by "$(child 2)" 9 CLOSED)" \
         "$(blocked_by "$(blocked_by "$(child 3)" 9 CLOSED)" 2 OPEN)"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(numbers "$output" ready)" = '[2]' ]
  [ "$(object "$output" | jq -c '.waiting[0] | {number, reasons, blocked_by}')" \
    = "{\"number\":3,\"reasons\":[\"blocked\"],\"blocked_by\":[\"$U/2\"]}" ]
}

@test "an assignee or any assigned:* label is a claim" {
  answer "$(child 2 | jq -c '.assignees = {totalCount: 1, nodes: [{login: "someone"}]}')" \
         "$(child 3 | jq -c '.labels = {totalCount: 2, nodes: [{name: "bug"}, {name: "assigned:other-bot"}]}')" \
         "$(child 4 | jq -c '.labels = {totalCount: 1, nodes: [{name: "bug"}]}')"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(numbers "$output" ready)" = '[4]' ]
  [ "$(object "$output" | jq -c '[.waiting[] | {number, reasons, assignees, claim_labels}]')" \
    = '[{"number":2,"reasons":["claimed"],"assignees":["someone"],"claim_labels":[]},{"number":3,"reasons":["claimed"],"assignees":[],"claim_labels":["assigned:other-bot"]}]' ]
}

@test "without a verdict on the parent, children need none" {
  answer "$(comment "$(child 2)" "${BOT}[bot]" "**Set review, round 1: CHANGES REQUESTED**")"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(object "$output" | jq .parent.spec_review)" = false ]
  [ "$(numbers "$output" ready)" = '[2]' ]
}

@test "under spec review, only a child whose latest verdict is READY is ready" {
  spec_reviewed
  answer "$(comment "$(comment "$(child 2)" "${BOT}[bot]" "**Set review, round 1: CHANGES REQUESTED**")" \
                    "${BOT}[bot]" "**Set review, round 2: READY**")" \
         "$(comment "$(comment "$(child 3)" "${BOT}[bot]" "**Set review, round 1: READY**")" \
                    "${BOT}[bot]" "**Spec review, round 2: CHANGES REQUESTED**")" \
         "$(child 4)"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(object "$output" | jq .parent.spec_review)" = true ]
  [ "$(numbers "$output" ready)" = '[2]' ]
  [ "$(object "$output" | jq -c '[.waiting[] | [.number, .reasons]]')" \
    = '[[3,["no-ready-verdict"]],[4,["no-ready-verdict"]]]' ]
}

@test "a verdict counts only from the slug, under either spelling, and only in the first line" {
  spec_reviewed
  answer "$(comment "$(child 2)" "$BOT" "**Set review, round 1: READY**")" \
         "$(comment "$(child 3)" "someone" "**Set review, round 1: READY**")" \
         "$(comment "$(child 4)" "${BOT}[bot]" $'Quoting the last round:\n**Set review, round 1: READY**')" \
         "$(comment "$(child 5)" "${BOT}[bot]" $'**Set review, round 1: READY**\r\n\ndetail')"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(numbers "$output" ready)" = '[2,5]' ]
}

@test "a project review or a reply from the bot is not a spec verdict" {
  spec_reviewed
  answer "$(comment "$(comment "$(child 2)" "${BOT}[bot]" "**Set review, round 1: READY**")" \
                    "${BOT}[bot]" "**Project review, round 1: CHANGES REQUESTED**")" \
         "$(comment "$(comment "$(child 3)" "${BOT}[bot]" "**Set review, round 1: READY**")" \
                    "${BOT}[bot]" "Thanks — that settles 3-B1.")"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(numbers "$output" ready)" = '[2,3]' ]
}

@test "every reason a child is held is listed, in sub-issue order" {
  spec_reviewed
  answer "$(child 5)" \
         "$(blocked_by "$(child 2 | jq -c '.assignees = {totalCount: 1, nodes: [{login: "me"}]}')" 5 OPEN)"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(object "$output" | jq -c '[.waiting[] | [.number, .reasons]]')" \
    = '[[5,["no-ready-verdict"]],[2,["blocked","claimed","no-ready-verdict"]]]' ]
}

@test "the output carries no GitHub field names" {
  answer "$(blocked_by "$(child 2)" 3 OPEN)" "$(child 4)"
  run "$READY" o/r 1 --slug=$BOT
  [ "$(object "$output" | jq -c '[paths | map(strings) | .[]] | unique')" \
    = '["assignees","blocked_by","claim_labels","number","parent","ready","reasons","spec_review","title","url","waiting"]' ]
}

@test "a parent with no sub-issues is an empty set, not an error" {
  answer
  run "$READY" o/r 1 --slug=$BOT
  [[ "$(line "$output")" == *"children=0 open=0 ready=0" ]]
}

@test "any page short of its total is set-overflow, so a hidden claim or blocker cannot read as ready" {
  local n
  for n in subIssues assignees labels blockedBy; do
    answer "$(child 2)"
    if [ "$n" = subIssues ]; then
      jq -c '.data.repository.issue.subIssues.totalCount = 2' "$ANSWER" > "$ANSWER.x"
    else
      jq -c ".data.repository.issue.subIssues.nodes[0].$n.totalCount = 101" "$ANSWER" > "$ANSWER.x"
    fi
    mv "$ANSWER.x" "$ANSWER"
    run "$READY" o/r 1 --slug=$BOT
    [[ "$output" == "result=ERROR reason=set-overflow now="* ]] || { echo "$n: $output"; false; }
    [ "$(wc -l <<<"$output")" -eq 1 ]
  done
}

@test "a null node or a payload that stops parsing is issue-query-shape" {
  answer null
  run "$READY" o/r 1 --slug=$BOT
  [[ "$output" == "result=ERROR reason=issue-query-shape now="* ]]
  answer "$(child 2 | jq -c '.blockedBy.nodes = [null] | .blockedBy.totalCount = 1')"
  run "$READY" o/r 1 --slug=$BOT
  [[ "$output" == "result=ERROR reason=issue-query-shape now="* ]]
  echo 'not json' > "$ANSWER"
  run "$READY" o/r 1 --slug=$BOT
  [[ "$output" == "result=ERROR reason=issue-query-shape now="* ]]
}

@test "a deleted author's comment is skipped, not a shape error" {
  spec_reviewed
  answer "$(child 2 | jq -c '.comments.nodes = [{author: null, body: "**Set review, round 1: READY**"}]')"
  run "$READY" o/r 1 --slug=$BOT
  [[ "$(line "$output")" == result=OK* ]]
  [ "$(numbers "$output" ready)" = '[]' ]
}

@test "an unresolvable issue is not-found, even though gh exits 1" {
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND"}]}' > "$ANSWER"
  touch "$GQL_EXIT"
  run "$READY" o/r 1 --slug=$BOT
  [ "$status" -eq 0 ]
  [[ "$output" == "result=ERROR reason=not-found now="* ]]
}

@test "no answer, or a null issue with another error, is issue-query" {
  touch "$GQL_EXIT"
  run "$READY" o/r 1 --slug=$BOT
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
  rm "$GQL_EXIT"
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"FORBIDDEN"}]}' > "$ANSWER"
  run "$READY" o/r 1 --slug=$BOT
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
}

@test "bad arguments are refused before any query, and the slug is required" {
  local args
  for args in "o/r 1" "o/r --slug=$BOT" "o 1 --slug=$BOT" "o/r/x 1 --slug=$BOT" \
              "o/r 1x --slug=$BOT" "o/r 1 2 --slug=$BOT" "o/r 1 --slug=$BOT --other" "o/r 1 --slug="; do
    # shellcheck disable=SC2086  # each case is a deliberately split argument list
    run "$READY" $args
    [[ "$output" == "result=ERROR reason=bad-args now="* ]] || { echo "$args: $output"; false; }
  done
  [ ! -s "$ARGV" ]
}

@test "another forge is refused before any query" {
  FORGE=gitlab run "$READY" o/r 1 --slug=$BOT
  [[ "$output" == "result=ERROR reason=unsupported-forge now="* ]]
  [ ! -s "$ARGV" ]
}

@test "the repo and number reach GraphQL as a String and an Int" {
  answer
  run "$READY" 0wner/123 7 --slug=$BOT
  grep -qx 'owner=0wner' "$ARGV"
  grep -qx 'repo=123' "$ARGV"
  grep -qx 'n=7' "$ARGV"
  # -f binds a String, -F an Int: the flag preceding each binding is what decides it.
  [ "$(grep -B1 -x 'repo=123' "$ARGV" | head -1)" = -f ]
  [ "$(grep -B1 -x 'n=7' "$ARGV" | head -1)" = -F ]
}
