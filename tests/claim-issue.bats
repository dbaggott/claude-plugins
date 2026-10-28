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
  [ "$output" = "result=OWN claim=c7f40c25 at=2026-01-02T00:00:00Z assignees=operator labels=assigned:agent-session" ]
}

@test "a claim carrying another session's id is foreign" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (0badc0de).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=0badc0de at=2026-01-02T00:00:00Z assignees=operator labels=assigned:agent-session" ]
}

# An issue can carry an older claim of this session's under a sibling's newer
# one, and matching any claim rather than the latest proceeds past the sibling.
@test "only the latest claim counts" {
  issue '["operator"]' '["assigned:agent-session"]' "[
    $(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z),
    $(comment 'Claimed by an agent session (0badc0de).' 2026-01-03T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=0badc0de at=2026-01-03T00:00:00Z assignees=operator labels=assigned:agent-session" ]
}

@test "a legacy claim with no id is foreign with no id" {
  issue '["operator"]' '["assigned:claude-code"]' \
    "[$(comment 'Claimed by Claude Code.' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=2026-01-02T00:00:00Z assignees=operator labels=assigned:claude-code" ]
}

@test "a claim made where no session id was exported has no id" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (id unavailable).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=2026-01-02T00:00:00Z assignees=operator labels=assigned:agent-session" ]
}

@test "marks applied by hand with no claim comment are foreign" {
  issue '[]' '["assigned:someone-else"]'
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=none assignees=none labels=assigned:someone-else" ]
}

@test "an own id is never matched when this session has none" {
  unset CLAUDE_CODE_SESSION_ID
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (id unavailable).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=2026-01-02T00:00:00Z assignees=operator labels=assigned:agent-session" ]
}

# The stamp line follows the claim line, so a line-anchored read of the claim
# must still find the claim, and the stamp's version must not be read as an id.
@test "a stamped claim is read by its claim line" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment $'Claimed by an agent session (c7f40c25).\n<!-- dnbg-workflow 2026.10.5 -->' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=OWN claim=c7f40c25 at=2026-01-02T00:00:00Z assignees=operator labels=assigned:agent-session" ]
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

# A teammate assigned by hand has no claim comment either, so the holders are
# what tells that claim from an agent session's id-less one.
@test "a person assigned by hand is named as the holder" {
  issue '["alice"]' '["enhancement"]'
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=none assignees=alice labels=none" ]
}

# --- --release ---------------------------------------------------------------

@test "--release of an own claim removes its label and the assignee, and says so" {
  issue '["operator"]' '["assigned:agent-session","assigned:other-tool"]' \
    "[$(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7 --release
  [ "$output" = "result=OK url=https://github.com/o/r/issues/7#issuecomment-1" ]
  grep -q '^issue edit 7 --repo o/r --remove-assignee @me --remove-label assigned:agent-session$' "$CALLS"
  ! grep -q 'assigned:other-tool' "$CALLS"
  grep -q '^issue comment 7 --repo o/r --body Released by an agent session (c7f40c25).$' "$CALLS"
}

@test "--release of a foreign claim is refused and writes nothing" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (0badc0de).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7 --release
  [[ "$output" == "result=ERROR reason=not-own now="* ]]
  ! grep -q '^issue ' "$CALLS"
}

@test "--release of an unclaimed issue is refused" {
  issue '[]' '[]'
  run "$CLAIM" o/r 7 --release
  [[ "$output" == "result=ERROR reason=not-own now="* ]]
  ! grep -q '^issue ' "$CALLS"
}

@test "--release with no session id is refused, since no claim can be its own" {
  unset CLAUDE_CODE_SESSION_ID
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (id unavailable).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7 --release
  [[ "$output" == "result=ERROR reason=not-own now="* ]]
}

@test "after a release the issue reads unclaimed, and a later claim is read past it" {
  local claimed released
  claimed=$(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z)
  released=$(comment 'Released by an agent session (c7f40c25).' 2026-01-03T00:00:00Z)
  issue '[]' '[]' "[$claimed, $released]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=UNCLAIMED claim=none at=none" ]
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$claimed, $released, $(comment 'Claimed by an agent session (0badc0de).' 2026-01-04T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=0badc0de at=2026-01-04T00:00:00Z assignees=operator labels=assigned:agent-session" ]
}

@test "a failed release write is an error" {
  issue '["operator"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z)]"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in "api graphql") cat "$GQL" ;; "issue edit") exit 1 ;; esac
EOF
  run "$CLAIM" o/r 7 --release
  [[ "$output" == "result=ERROR reason=claim-write "* ]]
}

@test "--release removes the configured label" {
  issue '["operator"]' '["assigned:bot-x"]' \
    "[$(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" o/r 7 --release --label=assigned:bot-x
  [[ "$output" == result=OK* ]]
  grep -q -- '--remove-label assigned:bot-x$' "$CALLS"
}

# A release leaves no claim behind it even while another holder's marks remain,
# so the released session's id is never read back as a live claim.
@test "marks left after a release read as foreign with no id" {
  issue '["alice"]' '["assigned:other-tool"]' "[
    $(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z),
    $(comment 'Released by an agent session (c7f40c25).' 2026-01-03T00:00:00Z)]"
  run "$CLAIM" o/r 7
  [ "$output" = "result=FOREIGN claim=none at=none assignees=alice labels=assigned:other-tool" ]
  run "$CLAIM" o/r 7 --release
  [[ "$output" == "result=ERROR reason=not-own now="* ]]
}

@test "--release takes no other mode's flags" {
  run "$CLAIM" o/r 7 --release --claim
  [[ "$output" == *"reason=bad-args"* ]]
  run "$CLAIM" o/r 7 --release --stamp=2026.10.5
  [[ "$output" == *"reason=bad-args"* ]]
  [ ! -s "$CALLS" ]
}

# --- --as=<role> -------------------------------------------------------------
#
# A copy of the scripts beside fixture roles (role-tree.bash), so a role that
# falls back and one that has an App can both be exercised. Each gh call is
# logged with the token it ran under.

bats_require_minimum_version 1.5.0
load role-tree

as_tree() {
  make_role_tree
  stub_forge
  add_role author operator
  CLAIM="$TREE/scripts/claim-issue.sh"
}

@test "--as with a fallback role assigns the operator and posts as the operator" {
  as_tree
  run "$CLAIM" acme/r 7 --claim --as=author
  [ "$output" = "result=OK claim=c7f40c25 url=https://github.com/acme/r/issues/7#issuecomment-1 as=operator-login fallback=unconfigured" ]
  grep -q '^gh issue edit 7 --repo acme/r --add-assignee operator-login --add-label assigned:agent-session token=none$' "$NET_LOG"
  grep -q '^gh issue comment 7 .* token=none$' "$NET_LOG"
  ! grep -q -- '@me' "$NET_LOG"
}

@test "--as with a configured role writes under its App, still assigning the operator" {
  as_tree
  configure_role author 7 agent-author-t
  run "$CLAIM" acme/r 7 --claim --as=author
  [ "$output" = "result=OK claim=c7f40c25 url=https://github.com/acme/r/issues/7#issuecomment-1 as=agent-author-t" ]
  grep -q "^gh label create assigned:agent-session .* token=$STUB_TOKEN\$" "$NET_LOG"
  grep -q "^gh issue edit 7 --repo acme/r --add-assignee operator-login --add-label assigned:agent-session token=$STUB_TOKEN\$" "$NET_LOG"
  grep -q "^gh issue comment 7 .* token=$STUB_TOKEN\$" "$NET_LOG"
}

@test "--as with a role the resolver refuses writes nothing" {
  as_tree
  run "$CLAIM" acme/r 7 --claim --as=reviewer
  [[ "$output" == *"result=ERROR reason=role now="* ]]
  ! grep -q '^gh label\|^gh issue' "$NET_LOG"
}

@test "--as in check mode adds the operator's login to OWN and FOREIGN" {
  as_tree
  export GQL="$BATS_TEST_TMPDIR/gql.json"
  issue '["operator-login"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" acme/r 7 --as=author
  [ "$output" = "result=OWN claim=c7f40c25 at=2026-01-02T00:00:00Z assignees=operator-login labels=assigned:agent-session operator=operator-login" ]
  issue '["someone"]' '[]'
  run "$CLAIM" acme/r 7 --as=author
  [ "$output" = "result=FOREIGN claim=none at=none assignees=someone labels=none operator=operator-login" ]
  issue '[]' '[]'
  run "$CLAIM" acme/r 7 --as=author
  [ "$output" = "result=UNCLAIMED claim=none at=none" ]
}

@test "--as with no role name is a bad argument" {
  run "$CLAIM" o/r 7 --as=
  [[ "$output" == "result=ERROR reason=bad-args"* ]]
}

@test "--as mints once for all three marks" {
  as_tree
  configure_role author 7 agent-author-t
  run "$CLAIM" acme/r 7 --claim --as=author
  [[ "$output" == "result=OK "* ]]
  [ "$(grep -c '/access_tokens$' "$NET_LOG")" -eq 1 ]
}

@test "--as with a credential that fails at write time is a role error, and writes nothing" {
  as_tree
  configure_role author 7 agent-author-t
  run --separate-stderr "$CLAIM" elsewhere/r 7 --claim --as=author
  [[ "$output" == "result=ERROR reason=role now="* ]]
  ! grep -q '^gh label\|^gh issue' "$NET_LOG"
}

# The shipped orchestrator role, which claims issues for its authors.

@test "--as=orchestrator with no orchestrator App claims as the operator, and says so" {
  as_tree
  ship_role orchestrator
  run --separate-stderr "$CLAIM" acme/r 7 --claim --as=orchestrator
  [ "$output" = "result=OK claim=c7f40c25 url=https://github.com/acme/r/issues/7#issuecomment-1 as=operator-login fallback=unconfigured" ]
  grep -q '^gh issue comment 7 .* token=none$' "$NET_LOG"
}

@test "--as=orchestrator whose key command prints nothing claims nothing" {
  as_tree
  ship_role orchestrator
  export DNBG_ORCHESTRATOR_APP_ID=9 DNBG_ORCHESTRATOR_PRIVATE_KEY_COMMAND=true
  run --separate-stderr "$CLAIM" acme/r 7 --claim --as=orchestrator
  [[ "$output" == "result=ERROR reason=role now="* ]]
  ! grep -q '^gh label\|^gh issue' "$NET_LOG"
}

@test "--release --as removes the operator's login and posts under the role's App" {
  as_tree
  configure_role author 7 agent-author-t
  export GQL="$BATS_TEST_TMPDIR/gql.json"
  issue '["operator-login"]' '["assigned:agent-session"]' \
    "[$(comment 'Claimed by an agent session (c7f40c25).' 2026-01-02T00:00:00Z)]"
  run "$CLAIM" acme/r 7 --release --as=author
  [ "$output" = "result=OK url=https://github.com/acme/r/issues/7#issuecomment-1 as=agent-author-t" ]
  grep -q "^gh issue edit 7 --repo acme/r --remove-assignee operator-login --remove-label assigned:agent-session token=$STUB_TOKEN\$" "$NET_LOG"
  grep -q "^gh issue comment 7 .* token=$STUB_TOKEN\$" "$NET_LOG"
}
