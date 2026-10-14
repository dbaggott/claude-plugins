#!/usr/bin/env bats
#
# Tests for the claim script. `gh` is stubbed: the GraphQL read answers from a
# fixture, and the writes `--claim` makes are recorded rather than sent.

CLAIM="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/claim-issue.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export GQL="$BATS_TEST_TMPDIR/gql.json"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "api graphql") cat "$GQL" ;;
  "issue comment") echo "https://github.com/o/r/issues/7#issuecomment-1" ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  export CLAUDE_CODE_SESSION_ID=c7f40c25-0000-0000-0000-000000000000
}

# The issue as the query returns it.
issue() {  # <assignees-json> <labels-json> [comments-json]
  jq -cn --argjson a "$1" --argjson l "$2" --argjson c "${3:-[]}" '
    { data: { repository: { issue: {
        assignees: { nodes: ($a | map({login: .})) },
        labels:    { nodes: ($l | map({name: .})) },
        comments:  { nodes: $c } } } } }' > "$GQL"
}

comment() {  # <body> <iso>
  jq -cn --arg b "$1" --arg t "$2" '{body: $b, createdAt: $t}'
}

@test "no assignee and no claim label is unclaimed" {
  issue '[]' '["enhancement"]'
  run "$CLAIM" o/r 7
  [ "$output" = "result=UNCLAIMED claim=none at=none" ]
}

@test "a claim carrying this session's id is its own" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=OWN claim=c7f40c25 at=2026-01-02T00:00:00Z" ]
}

@test "a claim carrying another session's id is foreign" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (0badc0de).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=0badc0de at=2026-01-02T00:00:00Z" ]
}

# An issue can carry an older claim of this session's under a sibling's newer
# one, and matching any claim rather than the latest proceeds past the sibling.
@test "only the latest claim counts" {
  issue '["operator"]' '["assigned:agent-session"]' "[
    $(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z),
    $(comment 'Claimed by an agent session (0badc0de).' 2026-01-03T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=0badc0de at=2026-01-03T00:00:00Z" ]
}

@test "a legacy claim with no id is foreign with no id" {
  issue '["operator"]' '["assigned:claude-code"]' \
    "[$(comment 'Claimed by Claude Code.' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=2026-01-02T00:00:00Z" ]
}

@test "a claim made where no session id was exported has no id" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (id unavailable).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=2026-01-02T00:00:00Z" ]
}

@test "marks applied by hand with no claim comment are foreign" {
  issue '[]' '["assigned:someone-else"]'
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=none" ]
}

@test "an own id is never matched when this session has none" {
  unset CLAUDE_CODE_SESSION_ID
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (id unavailable).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=2026-01-02T00:00:00Z" ]
}

# The stamp line follows the claim line, so a line-anchored read of the claim
# must still find the claim, and the stamp's version must not be read as an id.
@test "a stamped claim is read by its claim line" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment $'Claimed by an agent session (c7f40c25).\n<!-- dnbg-workflow 2026.10.5 -->' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=OWN claim=c7f40c25 at=2026-01-02T00:00:00Z" ]
}

@test "--claim applies the label, the assignee, and the claim comment" {
  run "$CLAIM" o/r 7 --claim
  [ "$output" = "result=OK claim=c7f40c25 url=https://github.com/o/r/issues/7#issuecomment-1" ]
  grep -q '^label create assigned:agent-session --repo o/r' "$CALLS"
  grep -q '^issue edit 7 --repo o/r --add-assignee @me --add-label assigned:agent-session$' "$CALLS"
  grep -q '^issue comment 7 --repo o/r --body Claimed by an agent session (c7f40c25).$' "$CALLS"
}

@test "--claim uses the configured label and puts the stamp on its own line" {
  run "$CLAIM" o/r 7 --claim --label=assigned:bot-x --stamp=2026.10.5
  [[ "$output" == result=OK* ]]
  grep -q -- '--add-label assigned:bot-x$' "$CALLS"
  grep -qx '<!-- dnbg-workflow 2026.10.5 -->' "$CALLS"
}

@test "--claim with no session id says so rather than posting empty parentheses" {
  unset CLAUDE_CODE_SESSION_ID
  run "$CLAIM" o/r 7 --claim
  [[ "$output" == "result=OK claim=none "* ]]
  grep -q 'Claimed by an agent session (id unavailable).' "$CALLS"
}

@test "a failed write is an error, not a claim" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in "issue edit") exit 1 ;; esac
EOF
  run "$CLAIM" o/r 7 --claim
  [[ "$output" == "result=ERROR reason=claim-write "* ]]
}

@test "a label outside the assigned: namespace is refused" {
  run "$CLAIM" o/r 7 --claim --label=wip
  [[ "$output" == *"reason=bad-args"* ]]
  run "$CLAIM" o/r 7 --claim --label=assigned:
  [[ "$output" == *"reason=bad-args"* ]]
  [ ! -s "$CALLS" ]
}

@test "a stamp that could break the comment is refused" {
  run "$CLAIM" o/r 7 --claim '--stamp=1 -->'
  [[ "$output" == *"reason=bad-args"* ]]
}

@test "bad arguments are refused" {
  run "$CLAIM" o/r
  [[ "$output" == *"reason=bad-args"* ]]
  run "$CLAIM" o/r abc
  [[ "$output" == *"reason=bad-args"* ]]
  run "$CLAIM" nope 7
  [[ "$output" == *"reason=bad-args"* ]]
  run "$CLAIM" o/r 7 --nope
  [[ "$output" == *"reason=bad-args"* ]]
}

@test "an issue that does not resolve is not-found" {
  echo '{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND"}]}' > "$GQL"
  run "$CLAIM" o/r 7
  [[ "$output" == *"reason=not-found"* ]]
}

@test "an unreadable payload is a shape error, not unclaimed" {
  echo '{"data":{"repository":{"issue":{"labels":"x"}}}}' > "$GQL"
  run "$CLAIM" o/r 7
  [[ "$output" == *"reason=issue-query-shape"* ]]
}

@test "another forge is refused" {
  FORGE=gitlab run "$CLAIM" o/r 7
  [[ "$output" == *"reason=unsupported-forge"* ]]
}
