#!/usr/bin/env bats
#
# Tests for the decision-row script. It runs from a copy of the scripts beside
# the shipped orchestrator role (role-tree.bash). `gh` is stubbed over a
# comments file, which `issue comment` appends to, and over a parent body,
# which the GraphQL read answers from and `issue edit` replaces.

bats_require_minimum_version 1.5.0
load role-tree

setup() {
  make_role_tree
  stub_forge
  ship_role orchestrator
  ROW="$TREE/scripts/decision-row.sh"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  export COMMENTS="$BATS_TEST_TMPDIR/comments"; echo '[]' > "$COMMENTS"
  export BODY="$BATS_TEST_TMPDIR/body"
  export COMMENT_FAILS=0 EDIT_FAILS=0 CREATED
  CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$STUB/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
printf 'gh %s token=%s\n' "$*" "${GH_TOKEN:-none}" >> "$NET_LOG"
case "$1 $2" in
  "api user") echo operator-login ;;
  "api --paginate") cat "$COMMENTS" ;;
  "api repos/"*) echo "${CREATED:0:10}" ;;
  "issue comment")
    [ "$COMMENT_FAILS" = 0 ] || exit 1
    while [ "$#" -gt 0 ]; do [ "$1" = --body-file ] && f="$2"; shift; done
    id=$(( $(jq length "$COMMENTS") + 1 ))
    url="https://github.com/acme/r/issues/7#issuecomment-$id"
    jq --rawfile b "$f" --arg u "$url" \
      '. + [{body: $b, html_url: $u, created_at: env.CREATED}]' \
      "$COMMENTS" > "$COMMENTS.new" && mv "$COMMENTS.new" "$COMMENTS"
    echo "$url" ;;
  "api graphql")
    jq -n --rawfile b "$BODY" \
      '{data: {repository: {issue: {body: $b, lastEditedAt: "2026-10-14T00:00:00Z"}}}}' ;;
  "issue edit")
    [ "$EDIT_FAILS" = 0 ] || exit 1
    while [ "$#" -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$BODY"; shift; done ;;
esac
STUB
  chmod +x "$STUB/gh"
  printf '%s' '# Project

## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| 2026-10-01 | D1 | — | First | decided |

## Related
' > "$BODY"
}

ARGS=(--id=D4 --state=applied
  '--question=https://github.com/acme/r/issues/7#issuecomment-99'
  '--answer=Leave the body to the orchestrator.'
  '--basis=allowlist (a).')
PARENT=https://github.com/acme/p/issues/3
CHILD=https://github.com/acme/r/issues/7

posted() { jq -r '.[-1].body' "$COMMENTS"; }
comments() { grep -c '^issue comment' "$CALLS" || true; }
edits() { grep -c '^issue edit' "$CALLS" || true; }
today() { date -u +%Y-%m-%d; }

@test "the comment is the row, byte for byte, and no parent row is written without --parent" {
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --as=orchestrator
  [ "$output" = "result=OK comment=$CHILD#issuecomment-1 parent=none as=operator-login fallback=unconfigured" ]
  diff <(posted) - <<'EOF'
Decision log: D4 — applied

**Question:** https://github.com/acme/r/issues/7#issuecomment-99
**Answer:** Leave the body to the orchestrator.
**Basis:** allowlist (a).
EOF
  [ "$(jq -r '.[-1].body | endswith(".")' "$COMMENTS")" = true ]
  ! grep -q '^api graphql' "$CALLS" || false
  [ "$(edits)" = 0 ]
}

@test "--parent appends the table row linking the comment, with the answer as its entry" {
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [ "$output" = "result=OK comment=$CHILD#issuecomment-1 parent=OK as=operator-login fallback=unconfigured" ]
  diff <(posted) - <<'EOF'
Decision log: D4 — applied

**Question:** https://github.com/acme/r/issues/7#issuecomment-99
**Answer:** Leave the body to the orchestrator.
**Basis:** allowlist (a).
EOF
  grep -qxF "| $(today) | D4 | $CHILD | Leave the body to the orchestrator. ($CHILD#issuecomment-1) | applied |" "$BODY"
  grep -q '^issue edit 3 --repo acme/p ' "$CALLS"
}

@test "--entry and --table-state replace the answer and the state in the table row only" {
  run --separate-stderr "$ROW" acme/r 7 --id=D9 --state=decided \
    '--question=none, asked at dispatch' '--answer=Delegated: take the default on X.' --basis=operator \
    --parent="$PARENT" '--entry=Delegation of X' --table-state=applied --as=orchestrator
  [[ "$output" == "result=OK comment=$CHILD#issuecomment-1 parent=OK "* ]]
  [ "$(posted | head -n1)" = 'Decision log: D9 — decided' ]
  grep -qxF "| $(today) | D9 | $CHILD | Delegation of X ($CHILD#issuecomment-1) | applied |" "$BODY"
}

@test "a row posted on the parent itself has — in its Child cell" {
  run --separate-stderr "$ROW" Acme/R 7 --id=D9 --state=decided \
    '--question=none, asked at dispatch' '--answer=Delegated: X.' --basis=operator \
    --parent="https://github.com/acme/r/issues/7" --table-state=applied --as=orchestrator
  [[ "$output" == "result=OK "*" parent=OK "* ]]
  grep -qxF "| $(today) | D9 | — | Delegated: X. ($CHILD#issuecomment-1) | applied |" "$BODY"
}

@test "a | in the entry is escaped so it cannot split the cell" {
  run --separate-stderr "$ROW" acme/r 7 --id=D4 --state=decided --question=q \
    '--answer=Use a | b' --basis=b --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=OK "*" parent=OK "* ]]
  grep -qxF "| $(today) | D4 | $CHILD | Use a \\| b ($CHILD#issuecomment-1) | decided |" "$BODY"
  [ "$(posted | sed -n 4p)" = '**Answer:** Use a | b' ]
}

@test "a new comment's row takes the server's creation date, not the local clock's" {
  CREATED=2026-10-31T23:59:59Z
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=OK "*" parent=OK "* ]]
  grep -q '^api repos/acme/r/issues/comments/1 ' "$CALLS"
  grep -qxF "| 2026-10-31 | D4 | $CHILD | Leave the body to the orchestrator. ($CHILD#issuecomment-1) | applied |" "$BODY"
}

@test "a multi-line answer stays in the comment and is one line in the table" {
  run --separate-stderr "$ROW" acme/r 7 '--id=Operator check | A' --state=decided --question=q \
    --answer=$'Changes needed:\n- one\n- two' --basis=operator --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=OK "*" parent=OK "* ]]
  diff <(posted) - <<'EOF2'
Decision log: Operator check | A — decided

**Question:** q
**Answer:** Changes needed:
- one
- two
**Basis:** operator
EOF2
  grep -qxF "| $(today) | Operator check \\| A | $CHILD | Changes needed: - one - two ($CHILD#issuecomment-1) | decided |" "$BODY"
}

@test "a re-run finds its identical comment, from any author, and posts and appends nothing" {
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=OK "* ]]
  # Another login's copy of the row, normalized with a trailing newline.
  jq '[.[0] | .body += "\n" | .html_url = "https://github.com/acme/r/issues/7#issuecomment-1"
       | .user = {login: "someone-else"}]' "$COMMENTS" > "$COMMENTS.new"
  mv "$COMMENTS.new" "$COMMENTS"
  before=$(cat "$BODY"); : > "$CALLS"
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [ "$output" = "result=OK comment=$CHILD#issuecomment-1 parent=OK as=operator-login fallback=unconfigured" ]
  [ "$(comments)" = 0 ]
  [ "$(edits)" = 0 ]
  [ "$(cat "$BODY")" = "$before" ]
}

@test "a reused comment's row takes the comment's date, not today's" {
  printf '%s' 'Decision log: D4 — applied

**Question:** https://github.com/acme/r/issues/7#issuecomment-99
**Answer:** Leave the body to the orchestrator.
**Basis:** allowlist (a).' | jq -Rs '[{body: ., html_url: "https://github.com/acme/r/issues/7#issuecomment-5",
    created_at: "2026-10-20T23:59:00Z"}]' > "$COMMENTS"
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=OK comment=$CHILD#issuecomment-5 parent=OK "* ]]
  [ "$(comments)" = 0 ]
  grep -qxF "| 2026-10-20 | D4 | $CHILD | Leave the body to the orchestrator. ($CHILD#issuecomment-5) | applied |" "$BODY"
}

@test "a different row on the issue is not reused" {
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --as=orchestrator
  run --separate-stderr "$ROW" acme/r 7 --id=D4 --state=decided --question=q --answer=a --basis=b --as=orchestrator
  [[ "$output" == "result=OK comment=$CHILD#issuecomment-2 "* ]]
  [ "$(comments)" = 2 ]
}

@test "a parent error still names the comment that was posted" {
  printf '## Other\n' > "$BODY"
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=ERROR reason=parent-section-missing comment=$CHILD#issuecomment-1 now="* ]]
  [ "$(comments)" = 1 ]
}

@test "a rejected parent write is parent-write, and a re-run completes it without a second comment" {
  export EDIT_FAILS=1
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=ERROR reason=parent-write comment=$CHILD#issuecomment-1 now="* ]]
  export EDIT_FAILS=0
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=OK comment=$CHILD#issuecomment-1 parent=OK "* ]]
  [ "$(comments)" = 1 ]
  [ "$(grep -c 'issuecomment-1) | applied |$' "$BODY")" = 1 ]
}

@test "a failed post is a comment error, and no parent row is written" {
  export COMMENT_FAILS=1
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [[ "$output" == "result=ERROR reason=comment now="* ]]
  [ "$(edits)" = 0 ]
}

@test "a configured role posts the comment and the parent row under its App" {
  configure_role orchestrator 9 agent-orchestrator-t
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=orchestrator
  [ "$output" = "result=OK comment=$CHILD#issuecomment-1 parent=OK as=agent-orchestrator-t" ]
  grep -q "^gh issue comment 7 --repo acme/r --body-file .* token=$STUB_TOKEN\$" "$NET_LOG"
  grep -q "^gh issue edit 3 --repo acme/p --body-file .* token=$STUB_TOKEN\$" "$NET_LOG"
  ! grep -o 'token=[^ ]*$' "$NET_LOG" | grep -vqx "token=$STUB_TOKEN" || false
}

@test "a role the resolver refuses reads and writes nothing" {
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --parent="$PARENT" --as=reviewer
  [[ "$output" == "result=ERROR reason=role now="* ]]
  ! grep -q '^gh ' "$NET_LOG" || false
  [ "$(jq length "$COMMENTS")" = 0 ]
}

@test "a configured role whose key command prints nothing posts nothing" {
  export DNBG_ORCHESTRATOR_APP_ID=9 DNBG_ORCHESTRATOR_PRIVATE_KEY_COMMAND=true
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --as=orchestrator
  [[ "$output" == "result=ERROR reason=role now="* ]]
  ! grep -q '^gh ' "$NET_LOG" || false
}

@test "another forge is refused before any request" {
  export FORGE=gitlab
  run --separate-stderr "$ROW" acme/r 7 "${ARGS[@]}" --as=orchestrator
  [[ "$output" == "result=ERROR reason=unsupported-forge now="* ]]
  ! grep -q '^gh ' "$NET_LOG" || false
}

bad() {
  run --separate-stderr "$ROW" "$@"
  [[ "$output" == "result=ERROR reason=bad-args "* ]] || { echo "accepted: $*"; return 1; }
}

@test "malformed calls are refused before any request" {
  bad acme/r 7 "${ARGS[@]}"
  bad acme/r 7 "${ARGS[@]}" --as=
  bad acme/r 7 --id=D4 --state=done --question=q --answer=a --basis=b --as=orchestrator
  bad acme/r 7 --id=D4 --state=decided --question=q --basis=b --as=orchestrator
  bad acme/r 7 --id=$'D\n4' --state=decided --question=q --answer=a --basis=b --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --parent= --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --parent="$PARENT" --entry= --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --entry=e --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --table-state=applied --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --parent="$PARENT" --table-state=done --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --parent=acme/p#3 --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --parent=https://github.com/acme/p/pull/3 --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --id=D5 --as=orchestrator
  bad acme/r 7 "${ARGS[@]}" --bogus=x --as=orchestrator
  bad acme/r 07 "${ARGS[@]}" --as=orchestrator
  bad acme 7 "${ARGS[@]}" --as=orchestrator
  ! grep -q '^gh ' "$NET_LOG" || false
}
