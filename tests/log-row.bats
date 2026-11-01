#!/usr/bin/env bats
#
# Tests for the log-append script. `gh` is stubbed over one body file: the
# GraphQL read answers from it, and `issue edit --body-file` replaces it unless
# LOSE names how many writes a concurrent writer overwrites first.

LOG="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/log-row.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export BODY="$BATS_TEST_TMPDIR/body"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  export LOST="$BATS_TEST_TMPDIR/lost"; echo 0 > "$LOST"
  export LOSE=0 EDIT_FAILS=0
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "api graphql")
    jq -n --rawfile b "$BODY" \
      '{data: {repository: {issue: {body: $b, lastEditedAt: "2026-10-14T00:00:00Z"}}}}' ;;
  "issue edit")
    [ "$EDIT_FAILS" = 0 ] || exit 1
    n=$(cat "$LOST")
    if [ "$n" -lt "$LOSE" ]; then echo $((n + 1)) > "$LOST"; exit 0; fi
    while [ "$#" -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$BODY"; shift; done ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

body() { printf '%s' "$1" > "$BODY"; }
edits() { grep -c '^issue edit' "$CALLS" || true; }

TRACKING='# Project

## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| 2026-10-01 | D1 | — | First | decided |

## Findings log

- **2026-10-02.** A gap in the export (author on https://github.com/o/r/issues/2)

## Related
'

@test "a row goes after the table's last row, and the rest of the body is kept" {
  body "$TRACKING"
  run "$LOG" o/r 7 --table="Decision log" --row='| 2026-10-14 | D2 | — | Second | proposed |'
  [ "$output" = "result=OK appended=1 body_edited=2026-10-14T00:00:00Z body_chars=$(jq -Rrs length "$BODY")" ]
  diff <(sed -n '6,9p' "$BODY") - <<'EOF'
| --- | --- | --- | --- | --- |
| 2026-10-01 | D1 | — | First | decided |
| 2026-10-14 | D2 | — | Second | proposed |

EOF
  grep -qx -- '- \*\*2026-10-02.\*\* A gap in the export (author on https://github.com/o/r/issues/2)' "$BODY"
  grep -qx '## Related' "$BODY"
}

@test "bullets go after the list's last item, in the order given" {
  body "$TRACKING"
  run "$LOG" o/r 7 --bullet="Findings log" --text='**2026-10-14.** One' --text='**2026-10-14.** Two'
  [[ "$output" == "result=OK appended=2 "* ]]
  diff <(sed -n '/^## Findings log/,/^## Related/p' "$BODY") - <<'EOF'
## Findings log

- **2026-10-02.** A gap in the export (author on https://github.com/o/r/issues/2)
- **2026-10-14.** One
- **2026-10-14.** Two

## Related
EOF
}

@test "an empty section gets a blank line between its heading and the first bullet" {
  body $'## Findings log\n## Next\n'
  run "$LOG" o/r 7 --bullet="Findings log" --text='first'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Findings log\n\n- first\n## Next' ]
}

@test "a first bullet under the section's prose is set off from it" {
  body $'## Findings log\n\nFindings about the code.\n\n## Next\n'
  run "$LOG" o/r 7 --bullet="Findings log" --text='first'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Findings log\n\nFindings about the code.\n\n- first\n\n## Next' ]
}

# A sub-heading belongs to the section; a sibling heading ends it.
@test "the section runs through deeper headings to the next sibling" {
  body $'## Findings log\n- a\n### Older\n- b\n## Next\n- c\n'
  run "$LOG" o/r 7 --bullet="Findings log" --text='new'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Findings log\n- a\n### Older\n- b\n- new\n## Next\n- c' ]
}

@test "a body without the heading is refused and not written" {
  body $'# Project\n\n## Decisions\n\n| a |\n'
  run "$LOG" o/r 7 --table="Decision log" --row='| x |'
  [[ "$output" == "result=ERROR reason=section-missing "* ]]
  [ "$(edits)" = 0 ]
}

@test "a heading inside a code fence is not the section" {
  body $'# Project\n\n```markdown\n## Findings log\n```\n'
  run "$LOG" o/r 7 --bullet="Findings log" --text='x'
  [[ "$output" == "result=ERROR reason=section-missing "* ]]
}

@test "a table row with no table under the heading is refused" {
  body $'## Decision log\n\nNothing yet.\n'
  run "$LOG" o/r 7 --table="Decision log" --row='| x |'
  [[ "$output" == "result=ERROR reason=table-missing "* ]]
  [ "$(edits)" = 0 ]
}

@test "a line the section already holds is not appended or written again" {
  body "$TRACKING"
  run "$LOG" o/r 7 --table="Decision log" --row='| 2026-10-01 | D1 | — | First | decided |'
  [[ "$output" == "result=OK appended=0 "* ]]
  [ "$(edits)" = 0 ]
}

@test "a line given twice in one call is appended once" {
  body "$TRACKING"
  run "$LOG" o/r 7 --bullet="Findings log" --text='x' --text='x'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(grep -cx -- '- x' "$BODY")" = 1 ]
}

@test "a body with no final newline gains none" {
  body $'## Findings log\n- a'
  run "$LOG" o/r 7 --bullet="Findings log" --text='b'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(od -An -c "$BODY" | tr -d ' \n')" = '##Findingslog\n-a\n-b' ]
}

# A fenced example table, or a fenced copy of the row, is not the log.
@test "lines inside a code fence are neither the anchor nor already present" {
  body $'## Decision log\n\n| a |\n| --- |\n| r1 |\n\nExample:\n\n```\n| r2 |\n~~~\n| r3 |\n```\n'
  run "$LOG" o/r 7 --table="Decision log" --row='| r2 |'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(sed -n 6p "$BODY")" = '| r2 |' ]
  [ "$(grep -cx '| r2 |' "$BODY")" = 2 ]
}

@test "a heading with a backslash is matched literally" {
  body $'## Notes \\ misc\n- a\n'
  run "$LOG" o/r 7 --bullet='Notes \ misc' --text='b'
  [[ "$output" == "result=OK appended=1 "* ]]
}

@test "seven hashes are not a heading" {
  body $'####### Findings log\n- a\n'
  run "$LOG" o/r 7 --bullet="Findings log" --text='b'
  [[ "$output" == "result=ERROR reason=section-missing "* ]]
}

@test "a write a concurrent writer replaced is made again on the new body" {
  body "$TRACKING"
  LOSE=1 run "$LOG" o/r 7 --bullet="Findings log" --text='kept'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(edits)" = 2 ]
  grep -qx -- '- kept' "$BODY"
}

@test "a write that never lands is reported lost after the last attempt" {
  body "$TRACKING"
  LOSE=99 MAX_WRITES=3 run "$LOG" o/r 7 --bullet="Findings log" --text='gone'
  [[ "$output" == "result=ERROR reason=write-lost "* ]]
  [ "$(edits)" = 3 ]
}

@test "a rejected write is reported as one" {
  body "$TRACKING"
  EDIT_FAILS=1 run "$LOG" o/r 7 --bullet="Findings log" --text='x'
  [[ "$output" == "result=ERROR reason=write "* ]]
}

@test "a CRLF body keeps CRLF on the inserted line" {
  body $'## Findings log\r\n- a\r\n'
  run "$LOG" o/r 7 --bullet="Findings log" --text='b'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Findings log\r\n- a\r\n- b\r' ]
}

@test "an unreadable issue is a query error" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/gh"
  run "$LOG" o/r 7 --bullet="Findings log" --text='x'
  [[ "$output" == "result=ERROR reason=issue-query "* ]]
}

bad() { run "$LOG" "$@"; [[ "$output" == "result=ERROR reason=bad-args "* ]] || { echo "accepted: $*"; return 1; }; }

@test "malformed calls are refused before any request" {
  body "$TRACKING"
  bad o/r 7 --table="Decision log" --row='not a row'
  bad o/r 7 --bullet="Findings log" --row='| x |'
  bad o/r 7 --table="Decision log" --text='x'
  bad o/r 7 --table="Decision log"
  bad o/r 7 --table="Decision log" --bullet="Findings log" --text='x'
  bad o/r 7 --bullet="Findings log" --text=$'a\nb'
  bad o/r 07 --bullet="Findings log" --text='x'
  bad o/r --bullet="Findings log" --text='x'
  [ ! -s "$CALLS" ]
}

@test "--as with no role name is a bad argument" {
  bad o/r 7 --bullet="Findings log" --text='x' --as=
  [ ! -s "$CALLS" ]
}

# --- --set-state -------------------------------------------------------------

# D1 has two rows, one per child, so the ID alone does not pick one out.
STATES='# Project

## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| 2026-10-01 | D1 | https://github.com/o/r/issues/2 | First | decided |
| 2026-10-02 | D1 | https://github.com/o/r/issues/3 | First | decided |
| 2026-10-03 | D2 | — | Second | proposed |

## Related

- after
'
D1_2='| 2026-10-01 | D1 | https://github.com/o/r/issues/2 | First | decided |'
D1_3='| 2026-10-02 | D1 | https://github.com/o/r/issues/3 | First | decided |'
D2='| 2026-10-03 | D2 | — | Second | proposed |'

@test "--set-state changes one row's last cell and no other byte" {
  body "$STATES"
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D1_2"
  [ "$output" = "result=OK updated=1 body_edited=2026-10-14T00:00:00Z body_chars=$(jq -Rrs length "$BODY")" ]
  diff "$BODY" <(printf '%s' "${STATES/"$D1_2"/${D1_2%decided |}applied |}")
  [ "$(edits)" = 1 ]
}

@test "--set-state keeps the last cell's own spacing" {
  body $'## Decision log\n| a | b |\n| --- | --- |\n| x |decided|\n| y |   decided  |\n'
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row='| x |decided|' --row='| y |   decided  |'
  [[ "$output" == "result=OK updated=2 "* ]]
  [ "$(cat "$BODY")" = $'## Decision log\n| a | b |\n| --- | --- |\n| x |applied|\n| y |   applied  |' ]
}

@test "--set-state changes several rows in one write" {
  body "$STATES"
  run "$LOG" o/r 7 --table="Decision log" --set-state=decided --row="$D1_3" --row="$D2"
  [[ "$output" == "result=OK updated=1 "* ]]
  [ "$(edits)" = 1 ]
  body "$STATES"; : > "$CALLS"
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D1_3" --row="$D2"
  [[ "$output" == "result=OK updated=2 "* ]]
  [ "$(edits)" = 1 ]
  grep -qx '| 2026-10-02 | D1 | https://github.com/o/r/issues/3 | First | applied |' "$BODY"
  grep -qx '| 2026-10-03 | D2 | — | Second | applied |' "$BODY"
  grep -qx "$D1_2" "$BODY"
}

@test "--set-state on a row already in the target state is done, and writes nothing" {
  body "$STATES"
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D1_2"
  : > "$CALLS"
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D1_2"
  [[ "$output" == "result=OK updated=0 "* ]]
  [ "$(edits)" = 0 ]
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied \
    --row='| 2026-10-01 | D1 | https://github.com/o/r/issues/2 | First | applied |'
  [[ "$output" == "result=OK updated=0 "* ]]
  [ "$(edits)" = 0 ]
}

@test "--set-state on a row that matches nothing is row-missing, and writes nothing" {
  body "$STATES"
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row='| 2026-10-09 | D9 | — | None | decided |'
  [[ "$output" == "result=ERROR reason=row-missing body_edited=2026-10-14T00:00:00Z now="* ]]
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D1_2" --row='| 2026-10-09 | D9 | — | None | decided |'
  [[ "$output" == "result=ERROR reason=row-missing "* ]]
  [ "$(edits)" = 0 ]
  diff "$BODY" <(printf '%s' "$STATES")
}

@test "--set-state leaves a matching line in a code fence or under another heading" {
  body $'## Decision log\n\n| a | b |\n| --- | --- |\n| x | decided |\n\n```\n| x | decided |\n```\n\n## Other\n\n| x | decided |\n'
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row='| x | decided |'
  [[ "$output" == "result=OK updated=1 "* ]]
  [ "$(sed -n 5p "$BODY")" = '| x | applied |' ]
  [ "$(grep -cx '| x | decided |' "$BODY")" = 2 ]
}

@test "--set-state on a fenced line alone is row-missing" {
  body $'## Decision log\n\n| a | b |\n| --- | --- |\n\n```\n| x | decided |\n```\n'
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row='| x | decided |'
  [[ "$output" == "result=ERROR reason=row-missing "* ]]
  [ "$(edits)" = 0 ]
}

@test "--set-state keeps CRLF on the changed line" {
  body $'## Decision log\r\n| a | b |\r\n| x | decided |\r\n'
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row='| x | decided |'
  [[ "$output" == "result=OK updated=1 "* ]]
  [ "$(od -An -c "$BODY" | tr -d ' \n')" = '##Decisionlog\r\n|a|b|\r\n|x|applied|\r\n' ]
}

@test "--set-state on a body with no final newline adds none" {
  body $'## Decision log\n| a | b |\n| x | decided |'
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row='| x | decided |'
  [[ "$output" == "result=OK updated=1 "* ]]
  [ "$(od -An -c "$BODY" | tr -d ' \n')" = '##Decisionlog\n|a|b|\n|x|applied|' ]
}

@test "--set-state remakes a write a concurrent writer replaced, and confirms it" {
  body "$STATES"
  LOSE=1 run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D2"
  [[ "$output" == "result=OK updated=1 "* ]]
  [ "$(edits)" = 2 ]
  [ "$(grep -c '^api graphql' "$CALLS")" = 3 ]
  grep -qx '| 2026-10-03 | D2 | — | Second | applied |' "$BODY"
}

@test "--set-state reports a write that never lands as lost" {
  body "$STATES"
  LOSE=99 MAX_WRITES=2 run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D2"
  [[ "$output" == "result=ERROR reason=write-lost "* ]]
  [ "$(edits)" = 2 ]
}

@test "--set-state changes every identical line a given row matches" {
  body $'## Decision log\n| a | b |\n| x | decided |\n| y | decided |\n| x | decided |\n'
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row='| x | decided |'
  [[ "$output" == "result=OK updated=2 "* ]]
  [ "$(cat "$BODY")" = $'## Decision log\n| a | b |\n| x | applied |\n| y | decided |\n| x | applied |' ]
}

@test "--set-state counts a line once when its row is given twice" {
  body "$STATES"
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D2" --row="$D2"
  [[ "$output" == "result=OK updated=1 "* ]]
}

# The stub's write lands, then a concurrent writer replaces the body with one
# that no longer holds the row; the confirming read finds it gone.
@test "--set-state reports a row removed after its write landed as row-missing" {
  body "$STATES"
  export GONE="$BATS_TEST_TMPDIR/gone"
  printf '%s' "${STATES/"$D2"$'\n'/}" > "$GONE"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "api graphql")
    jq -n --rawfile b "$BODY" \
      '{data: {repository: {issue: {body: $b, lastEditedAt: "2026-10-15T00:00:00Z"}}}}' ;;
  "issue edit") cp "$GONE" "$BODY" ;;
esac
EOF
  run "$LOG" o/r 7 --table="Decision log" --set-state=applied --row="$D2"
  [[ "$output" == "result=ERROR reason=row-missing body_edited=2026-10-15T00:00:00Z now="* ]]
  [ "$(edits)" = 1 ]
}

@test "--set-state with a bullet section, an unknown state, or twice is a bad argument" {
  body "$STATES"
  bad o/r 7 --bullet="Findings log" --set-state=applied --text='x'
  bad o/r 7 --set-state=applied --bullet="Findings log" --text='x'
  bad o/r 7 --table="Decision log" --set-state=done --row="$D2"
  bad o/r 7 --table="Decision log" --set-state= --row="$D2"
  bad o/r 7 --table="Decision log" --set-state=applied --set-state=applied --row="$D2"
  bad o/r 7 --table="Decision log" --set-state=applied
  [ ! -s "$CALLS" ]
}

# --- --as=<role> -------------------------------------------------------------
#
# A copy of the scripts beside the shipped orchestrator role (role-tree.bash).
# The body stub above, with each call also logged with the token it ran under.

bats_require_minimum_version 1.5.0
load role-tree

as_tree() {
  make_role_tree
  stub_forge
  ship_role orchestrator
  LOG="$TREE/scripts/log-row.sh"
  cat > "$STUB/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
printf 'gh %s token=%s\n' "$*" "${GH_TOKEN:-none}" >> "$NET_LOG"
case "$1 $2" in
  "api user") echo operator-login ;;
  "api graphql")
    jq -n --rawfile b "$BODY" \
      '{data: {repository: {issue: {body: $b, lastEditedAt: "2026-10-14T00:00:00Z"}}}}' ;;
  "issue edit")
    while [ "$#" -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$BODY"; shift; done ;;
esac
STUB
  chmod +x "$STUB/gh"
  body "$TRACKING"
}

@test "--as with a role that falls back writes as the operator, and says so" {
  as_tree
  run --separate-stderr "$LOG" acme/r 7 --bullet="Findings log" --text='x' --as=orchestrator
  [ "$output" = "result=OK appended=1 body_edited=2026-10-14T00:00:00Z body_chars=$(jq -Rrs length "$BODY") as=operator-login fallback=unconfigured" ]
  grep -q '^gh issue edit 7 --repo acme/r --body-file .* token=none$' "$NET_LOG"
  grep -qx -- '- x' "$BODY"
}

@test "--as with a configured role reads and writes under its App, minting once" {
  as_tree
  configure_role orchestrator 9 agent-orchestrator-t
  run --separate-stderr "$LOG" acme/r 7 --table="Decision log" --row='| 2026-10-14 | D2 | — | Second | proposed |' --as=orchestrator
  [[ "$output" == "result=OK appended=1 "*" as=agent-orchestrator-t" ]]
  grep -q "^gh issue edit 7 --repo acme/r --body-file .* token=$STUB_TOKEN\$" "$NET_LOG"
  # The query spans lines; each read's log entry ends on its variables.
  grep -q -- "-F n=7 token=$STUB_TOKEN\$" "$NET_LOG"
  ! grep -- '-F n=7 token=' "$NET_LOG" | grep -vq "token=$STUB_TOKEN\$" || false
  [ "$(grep -c '/access_tokens$' "$NET_LOG")" -eq 1 ]
}

@test "--as passes an error through without an as= field" {
  as_tree
  configure_role orchestrator 9 agent-orchestrator-t
  run --separate-stderr "$LOG" acme/r 7 --bullet="No such section" --text='x' --as=orchestrator
  [[ "$output" == "result=ERROR reason=section-missing now="* ]]
  [[ "$output" != *"as="* ]]
}

@test "--as with a configured role whose key command prints nothing posts nothing" {
  as_tree
  export DNBG_ORCHESTRATOR_APP_ID=9 DNBG_ORCHESTRATOR_PRIVATE_KEY_COMMAND=true
  run --separate-stderr "$LOG" acme/r 7 --bullet="Findings log" --text='x' --as=orchestrator
  [[ "$output" == "result=ERROR reason=role now="* ]]
  [[ "$stderr" == *"produced no output"* ]]
  ! grep -q '^gh ' "$NET_LOG" || false
  ! grep -qx -- '- x' "$BODY"
}

@test "--as with a role the resolver refuses reads and writes nothing" {
  as_tree
  run --separate-stderr "$LOG" acme/r 7 --bullet="Findings log" --text='x' --as=reviewer
  [[ "$output" == "result=ERROR reason=role now="* ]]
  ! grep -q '^gh ' "$NET_LOG"
}

@test "--as passes --set-state through, and its result carries the as= tail" {
  as_tree
  configure_role orchestrator 9 agent-orchestrator-t
  run --separate-stderr "$LOG" acme/r 7 --table="Decision log" --set-state=applied \
    --row='| 2026-10-01 | D1 | — | First | decided |' --as=orchestrator
  [[ "$output" == "result=OK updated=1 "*" as=agent-orchestrator-t" ]]
  grep -qx '| 2026-10-01 | D1 | — | First | applied |' "$BODY"
}

@test "--as passes row-missing through with its body_edited field" {
  as_tree
  run --separate-stderr "$LOG" acme/r 7 --table="Decision log" --set-state=applied \
    --row='| 2026-10-09 | D9 | — | None | decided |' --as=orchestrator
  [[ "$output" == "result=ERROR reason=row-missing body_edited=2026-10-14T00:00:00Z now="* ]]
}
