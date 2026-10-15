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

## Friction log

- **2026-10-02.** Slow watch (author on https://github.com/o/r/issues/2)

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
  grep -qx -- '- \*\*2026-10-02.\*\* Slow watch (author on https://github.com/o/r/issues/2)' "$BODY"
  grep -qx '## Related' "$BODY"
}

@test "bullets go after the list's last item, in the order given" {
  body "$TRACKING"
  run "$LOG" o/r 7 --bullet="Friction log" --text='**2026-10-14.** One' --text='**2026-10-14.** Two'
  [[ "$output" == "result=OK appended=2 "* ]]
  diff <(sed -n '/^## Friction log/,/^## Related/p' "$BODY") - <<'EOF'
## Friction log

- **2026-10-02.** Slow watch (author on https://github.com/o/r/issues/2)
- **2026-10-14.** One
- **2026-10-14.** Two

## Related
EOF
}

@test "an empty section gets a blank line between its heading and the first bullet" {
  body $'## Friction log\n## Next\n'
  run "$LOG" o/r 7 --bullet="Friction log" --text='first'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Friction log\n\n- first\n## Next' ]
}

@test "a first bullet under the section's prose is set off from it" {
  body $'## Friction log\n\nWhere the process hurt.\n\n## Next\n'
  run "$LOG" o/r 7 --bullet="Friction log" --text='first'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Friction log\n\nWhere the process hurt.\n\n- first\n\n## Next' ]
}

# A sub-heading belongs to the section; a sibling heading ends it.
@test "the section runs through deeper headings to the next sibling" {
  body $'## Friction log\n- a\n### Older\n- b\n## Next\n- c\n'
  run "$LOG" o/r 7 --bullet="Friction log" --text='new'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Friction log\n- a\n### Older\n- b\n- new\n## Next\n- c' ]
}

@test "a body without the heading is refused and not written" {
  body $'# Project\n\n## Decisions\n\n| a |\n'
  run "$LOG" o/r 7 --table="Decision log" --row='| x |'
  [[ "$output" == "result=ERROR reason=section-missing "* ]]
  [ "$(edits)" = 0 ]
}

@test "a heading inside a code fence is not the section" {
  body $'# Project\n\n```markdown\n## Friction log\n```\n'
  run "$LOG" o/r 7 --bullet="Friction log" --text='x'
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
  run "$LOG" o/r 7 --bullet="Friction log" --text='x' --text='x'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(grep -cx -- '- x' "$BODY")" = 1 ]
}

@test "a body with no final newline gains none" {
  body $'## Friction log\n- a'
  run "$LOG" o/r 7 --bullet="Friction log" --text='b'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(od -An -c "$BODY" | tr -d ' \n')" = '##Frictionlog\n-a\n-b' ]
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
  body $'####### Friction log\n- a\n'
  run "$LOG" o/r 7 --bullet="Friction log" --text='b'
  [[ "$output" == "result=ERROR reason=section-missing "* ]]
}

@test "a write a concurrent writer replaced is made again on the new body" {
  body "$TRACKING"
  LOSE=1 run "$LOG" o/r 7 --bullet="Friction log" --text='kept'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(edits)" = 2 ]
  grep -qx -- '- kept' "$BODY"
}

@test "a write that never lands is reported lost after the last attempt" {
  body "$TRACKING"
  LOSE=99 MAX_WRITES=3 run "$LOG" o/r 7 --bullet="Friction log" --text='gone'
  [[ "$output" == "result=ERROR reason=write-lost "* ]]
  [ "$(edits)" = 3 ]
}

@test "a rejected write is reported as one" {
  body "$TRACKING"
  EDIT_FAILS=1 run "$LOG" o/r 7 --bullet="Friction log" --text='x'
  [[ "$output" == "result=ERROR reason=write "* ]]
}

@test "a CRLF body keeps CRLF on the inserted line" {
  body $'## Friction log\r\n- a\r\n'
  run "$LOG" o/r 7 --bullet="Friction log" --text='b'
  [[ "$output" == "result=OK appended=1 "* ]]
  [ "$(cat "$BODY")" = $'## Friction log\r\n- a\r\n- b\r' ]
}

@test "an unreadable issue is a query error" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/gh"
  run "$LOG" o/r 7 --bullet="Friction log" --text='x'
  [[ "$output" == "result=ERROR reason=issue-query "* ]]
}

bad() { run "$LOG" "$@"; [[ "$output" == "result=ERROR reason=bad-args "* ]] || { echo "accepted: $*"; return 1; }; }

@test "malformed calls are refused before any request" {
  body "$TRACKING"
  bad o/r 7 --table="Decision log" --row='not a row'
  bad o/r 7 --bullet="Friction log" --row='| x |'
  bad o/r 7 --table="Decision log" --text='x'
  bad o/r 7 --table="Decision log"
  bad o/r 7 --table="Decision log" --bullet="Friction log" --text='x'
  bad o/r 7 --bullet="Friction log" --text=$'a\nb'
  bad o/r 07 --bullet="Friction log" --text='x'
  bad o/r --bullet="Friction log" --text='x'
  [ ! -s "$CALLS" ]
}
