#!/usr/bin/env bats
#
# Tests for setting a child's parent and blockers. `gh` is stubbed: `issue view`
# serves the child's current relationships from JSON each test builds, and
# `issue edit` is recorded, failing with the forge's message when a test asks.

bats_require_minimum_version 1.5.0

SET="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/set-issue-relations.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export VIEW="$BATS_TEST_TMPDIR/view.json"
  export EDITS="$BATS_TEST_TMPDIR/edits"; : > "$EDITS"
  export REJECT="$BATS_TEST_TMPDIR/reject"   # holds the flag `issue edit` rejects
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue view")
    [ -f "$VIEW" ] || { echo "GraphQL: Could not resolve to an issue" >&2; exit 1; }
    cat "$VIEW" ;;
  "issue edit")
    printf '%s\n' "$*" >> "$EDITS"
    if [ -f "$REJECT" ] && [[ " $* " == *" $(cat "$REJECT") "* ]]; then
      echo "GraphQL: Validation failed (stub rejection)" >&2; exit 1
    fi ;;
  *) echo "unexpected gh call: $*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

# <parent-url|""> [blocker-url...] -> the child's current relationships.
current() {
  local parent="$1"; shift
  printf '%s\n' "$@" | jq -Rcs --arg p "$parent" --arg self "$(url 7)" '
    [split("\n")[] | select(. != "") | {url: .}] as $nodes
    | {url: $self, parent: (if $p == "" then null else {url: $p} end),
       blockedBy: {nodes: $nodes, totalCount: ($nodes | length)}}' > "$VIEW"
}
url() { echo "https://github.com/o/r/issues/$1"; }

@test "an unrelated child gets its parent and every blocker" {
  current ""
  run "$SET" o/r 7 --parent=1 --blocked-by=3,4
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK parent=1 blocked_by=3,4" ]
  [ "$(cat "$EDITS")" = "$(printf '%s\n' \
      'issue edit 7 --repo o/r --parent 1' \
      'issue edit 7 --repo o/r --add-blocked-by 3,4')" ]
}

@test "with no --blocked-by only the parent is written" {
  current ""
  run "$SET" o/r 7 --parent=1
  [ "$output" = "result=OK parent=1 blocked_by=" ]
  [ "$(cat "$EDITS")" = "issue edit 7 --repo o/r --parent 1" ]
}

@test "a second run over relationships already in place writes nothing" {
  current "$(url 1)" "$(url 3)" "$(url 4)"
  run "$SET" o/r 7 --parent=1 --blocked-by=3,4
  [ "$output" = "result=OK parent=1 blocked_by=3,4" ]
  [ ! -s "$EDITS" ]
}

@test "only the blockers missing are written, and existing extras are left alone" {
  current "$(url 1)" "$(url 3)" "$(url 9)"
  run "$SET" o/r 7 --parent=1 --blocked-by=3,4
  [ "$output" = "result=OK parent=1 blocked_by=3,4" ]
  [ "$(cat "$EDITS")" = "issue edit 7 --repo o/r --add-blocked-by 4" ]
}

@test "relationships match on the child's canonical repository, not the name passed" {
  current "$(url 1)" "$(url 3)"
  run "$SET" O/old-name 7 --parent=1 --blocked-by=3
  [ "$output" = "result=OK parent=1 blocked_by=3" ]
  [ ! -s "$EDITS" ]
}

@test "a same-numbered issue in another repository is not mistaken for the one named" {
  current "https://github.com/o/other/issues/1" "https://github.com/o/other/issues/3"
  run --separate-stderr "$SET" o/r 7 --parent=1 --blocked-by=3
  [[ "$output" == "result=ERROR reason=parent-conflict now="* ]]
}

@test "a child with a different parent is refused, not moved" {
  current "$(url 2)"
  run --separate-stderr "$SET" o/r 7 --parent=1 --blocked-by=3
  [ "$status" -eq 0 ]
  [[ "$output" == "result=ERROR reason=parent-conflict now="* ]]
  [[ "$stderr" == *"already has parent $(url 2)"* ]]
  [ ! -s "$EDITS" ]
}

@test "a rejected parent is surfaced with the forge's message, and no blocker is written" {
  current ""
  echo "--parent" > "$REJECT"
  run --separate-stderr "$SET" o/r 7 --parent=1 --blocked-by=3
  [[ "$output" == "result=ERROR reason=parent-rejected now="* ]]
  [[ "$stderr" == *"stub rejection"* ]]
  [ "$(cat "$EDITS")" = "issue edit 7 --repo o/r --parent 1" ]
}

@test "a rejected blocker is surfaced with the forge's message" {
  current "$(url 1)"
  echo "--add-blocked-by" > "$REJECT"
  run --separate-stderr "$SET" o/r 7 --parent=1 --blocked-by=3
  [[ "$output" == "result=ERROR reason=blocked-by-rejected now="* ]]
  [[ "$stderr" == *"stub rejection"* ]]
}

@test "a blocker list read only in part is refused, not taken as complete" {
  current "$(url 1)" "$(url 3)"
  jq '.blockedBy.totalCount = 101' "$VIEW" > "$VIEW.tmp" && mv "$VIEW.tmp" "$VIEW"
  run --separate-stderr "$SET" o/r 7 --parent=1 --blocked-by=4
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
  [[ "$stderr" == *"not read in full"* ]]
  [ ! -s "$EDITS" ]
}

@test "a child that cannot be read is an issue-query error, with nothing written" {
  run --separate-stderr "$SET" o/r 7 --parent=1
  [[ "$output" == "result=ERROR reason=issue-query now="* ]]
  [ ! -s "$EDITS" ]
}

@test "malformed arguments are refused before any forge call" {
  current ""
  for args in "" "o/r" "o/r 7" "or 7 --parent=1" "o/r/x 7 --parent=1" "o/r x --parent=1" \
              "o/r 7 --parent=" "o/r 7 --parent=a" "o/r 7 --parent=7" \
              "o/r 7 --parent=1 --parent=2" "o/r 7 --parent=1 --blocked-by=" \
              "o/r 7 --parent=1 --blocked-by=3,x" "o/r 7 --parent=1 --blocked-by=7" \
              "o/r 7 --parent=1 --blocked-by=3,,4" "o/r 7 --parent=1 --blocked-by=3,3" \
              "o/r 7 --parent=1 --blocked-by=3," "o/r 7 --parent=1 --blocked-by=,3" \
              "o/r 07 --parent=1" "o/r 7 --parent=01" "o/r 7 --parent=1 --blocked-by=3,03" \
              "o/r 7 --parent=1 --blocked-by=3 --blocked-by=4" "o/r 7 --parent=1 --other"; do
    # shellcheck disable=SC2086  # each case is a word list by design
    run "$SET" $args
    [[ "$output" == "result=ERROR reason=bad-args now="* ]] || { echo "accepted: $args"; false; }
  done
  [ ! -s "$EDITS" ]
}

@test "another forge is refused before any forge call" {
  current ""
  FORGE=gitlab run "$SET" o/r 7 --parent=1
  [[ "$output" == "result=ERROR reason=unsupported-forge now="* ]]
  [ ! -s "$EDITS" ]
}

@test "the GitHub assumption carries the forge marker" {
  grep -A1 'THE FORGE IS ASSUMED TO BE GITHUB' "$SET" \
    | grep -qF 'https://github.com/dbaggott/claude-plugins/issues/149'
}
