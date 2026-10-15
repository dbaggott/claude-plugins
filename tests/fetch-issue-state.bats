#!/usr/bin/env bats
#
# Tests for the batched issue fetch. It had no direct suite and was covered only
# transitively through watch-issue.bats's stub, which is how the `missing`
# ordering bug below survived: nothing exercised the path that computes it.

FETCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/fetch-issue-state.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export GQL="$BATS_TEST_TMPDIR/gql.json"
  export GQL_EXIT="$BATS_TEST_TMPDIR/gql_exit"
  export ARGV="$BATS_TEST_TMPDIR/argv"; : > "$ARGV"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ARGV"
cat "$GQL"
[ -f "$GQL_EXIT" ] && exit 1
exit 0
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

node() {  # <n> [state]
  jq -cn --arg n "$1" --arg st "${2:-OPEN}" '
    {number: ($n|tonumber), state: $st, lastEditedAt: null,
     comments: {totalCount: 0, nodes: []},
     closedByPullRequestsReferences: {nodes: []}, timelineItems: {nodes: []}}'
}
repo() {
  local acc='{}' i
  for i in "$@"; do acc=$(jq -c --argjson n "$i" '. + {("i"+($n.number|tostring)): $n}' <<<"$acc"); done
  jq -cn --argjson r "$acc" '{data:{repository:$r}}' > "$GQL"
}
obj() { sed '$d' <<<"$1"; }
line() { tail -1 <<<"$1"; }

# `comm` compares lexicographically. Sorting numerically makes it report issues
# that answered perfectly well as missing, and 9 against 10 is the smallest case
# — so a single deleted issue in a batch tells the caller healthy ones are gone.
@test "a missing issue is named without dragging healthy ones with it" {
  repo "$(node 10)"
  : > "$GQL_EXIT"
  run "$FETCH" o/r 9 10
  [[ "$(line "$output")" == *"missing=9"* ]]
  [[ "$(line "$output")" != *"missing=9,10"* ]]
  [ "$(obj "$output" | jq -r '[.issues[].number] | join(",")')" = 10 ]
}

@test "a number repeated in the arguments is not a missing issue" {
  repo "$(node 10)"
  run "$FETCH" o/r 10 10
  [[ "$(line "$output")" != *missing=* ]]
}

@test "every issue answering reports no missing at all" {
  repo "$(node 10)" "$(node 11)"
  run "$FETCH" o/r 10 11
  [[ "$(line "$output")" == "result=OK"* ]]
  [[ "$(line "$output")" != *missing=* ]]
  [ "$(obj "$output" | jq -r '.missing | length')" = 0 ]
}

# gh exits 1 on a null alias while returning valid data for the rest. Reading the
# status alone discards the issues that answered.
@test "a null alias does not discard the issues that answered" {
  jq -cn --argjson good "$(node 10)" \
    '{data:{repository:{i10:$good, i999:null}}, errors:[{type:"NOT_FOUND"}]}' > "$GQL"
  : > "$GQL_EXIT"
  run "$FETCH" o/r 10 999
  [[ "$(line "$output")" == "result=OK"* ]]
  [ "$(obj "$output" | jq -r '[.issues[].number] | join(",")')" = 10 ]
}

@test "every alias unresolvable is an error rather than an empty answer" {
  echo '{"data":{"repository":{"i999":null}}}' > "$GQL"
  run "$FETCH" o/r 999
  [[ "$output" == *"result=ERROR reason=issue-query"* ]]
}

@test "a payload that stops parsing is a shape error" {
  echo 'not json' > "$GQL"
  run "$FETCH" o/r 10
  [[ "$output" == *"reason=issue-query"* ]]
}

@test "the linked PRs from both sources arrive as one deduplicated list" {
  jq -cn '{data:{repository:{i10:{number:10,state:"OPEN",lastEditedAt:null,
     comments:{totalCount:0,nodes:[]},
     closedByPullRequestsReferences:{nodes:[{url:"https://x/pull/1"}]},
     timelineItems:{nodes:[{source:{url:"https://x/pull/1"}},{source:{url:"https://x/pull/2"}}]}}}}}' > "$GQL"
  run "$FETCH" o/r 10
  [ "$(obj "$output" | jq -r '.issues[0].linked_prs | join(",")')" = "https://x/pull/1,https://x/pull/2" ]
}

@test "a never-edited body is null rather than absent" {
  repo "$(node 10)"
  run "$FETCH" o/r 10
  [ "$(obj "$output" | jq -r '.issues[0] | has("body_edited")')" = true ]
  [ "$(obj "$output" | jq -r '.issues[0].body_edited')" = null ]
}

@test "a forge with no backend is refused rather than assumed" {
  repo "$(node 10)"
  FORGE=gitlab run "$FETCH" o/r 10
  [[ "$output" == *"reason=unsupported-forge"* ]]
}

@test "a missing repo or issue number is refused" {
  run "$FETCH" o/r
  [[ "$output" == *"reason=bad-args"* ]]
  run "$FETCH" notarepo 10
  [[ "$output" == *"reason=bad-args"* ]]
  run "$FETCH" o/r abc
  [[ "$output" == *"reason=bad-args"* ]]
}

# `-F` types the value, so an all-digit repo or owner is sent as a JSON NUMBER
# against `String!`. GitHub then refuses the whole query — `owner/2048` errors on
# every tick, reported as `issue-query` and indistinguishable from an outage, on
# a repo the watch can see perfectly well. The stub cannot emulate that
# coercion, so what is pinned is the flag form, which is the thing under control.
@test "the repo variables are bound untyped, so an all-digit name stays a string" {
  repo "$(node 1)"
  run "$FETCH" owner/2048 1
  grep -q -- '-f owner=' "$ARGV"
  grep -q -- '-f repo=' "$ARGV"
  ! grep -q -- '-F owner=' "$ARGV"
  ! grep -q -- '-F repo=' "$ARGV"
}
