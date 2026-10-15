#!/usr/bin/env bats
#
# The restart eval's offline parts: its fixtures, the predicates that decide the
# kill point and the verdict, the process-tree kill, and the GitHub writes with
# `gh` and the plugin's scripts stubbed. Nothing here starts an orchestrator.

bats_require_minimum_version 1.5.0
load trace-dir
load reap

EVAL="${BATS_TEST_DIRNAME}/evals/restart"
U=https://github.com/o/r/issues
VALUE=ahoy-20261014-1
CID=4242

setup() {
  contain_traces
  # shellcheck source=evals/restart/run.sh
  source "$EVAL/run.sh"
  REPO=o/r
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export LOG="$BATS_TEST_TMPDIR/log"; : > "$LOG"
  export BODIES="$BATS_TEST_TMPDIR/bodies"; mkdir -p "$BODIES"
  export FAIL_ON="${FAIL_ON:-}"
  cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$LOG"
[ -n "\$FAIL_ON" ] && [[ "\$*" == *"\$FAIL_ON"* ]] && exit 1
body=""; prev=""
for a in "\$@"; do [ "\$prev" = --body-file ] && body="\$a"; prev="\$a"; done
case "\$1 \$2" in
  "issue create")
    n=\$(( \$(ls "\$BODIES" | grep -c '^[0-9]') + 1 ))
    cp "\$body" "\$BODIES/\$n"
    echo "Creating issue in o/r"; echo "$U/\$n" ;;
  "issue edit")
    [ -z "\$body" ] || cp "\$body" "\$BODIES/edited-\${3##*/}" ;;
  "pr view") echo "\${PR_STATE:-OPEN}" ;;
esac
exit 0
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  DIR="$BATS_TEST_TMPDIR/run"; mkdir -p "$DIR"
}

# The parent as filed, with the children at $U/2 and $U/3.
fixture_parent() {
  render "$EVAL/fixtures/parent.md" RUN=20261014-1 DATE=2026-10-14 CHILD_A="$U/2" CHILD_B="$U/3"
}

# The fixture parent with R2 rewritten to the new value, a decision row in
# <state> appended to the log, or neither when an argument is empty.
decided_parent() {  # <r2: new|old> <row-state|"">
  local body
  body=$(fixture_parent)
  [ "$1" = new ] && body=${body//"holds the single line \`hello\`"/"holds the single line \`$VALUE\`"}
  if [ -n "$2" ]; then
    body=$(awk -v row="| 2026-10-14 | D2 | — | R2 becomes \`$VALUE\` ([comment](https://github.com/o/r/issues/1#issuecomment-$CID)) | $2 |" '
      { print } /^\| 2026-10-14 \| D1 / { print row }' <<< "$body")
  fi
  printf '%s\n' "$body"
}

@test "fixtures: every placeholder is filled, and child A never cites R2" {
  file_fixture "$DIR" 20261014-1
  run ! grep -l '{{' "$BODIES"/*
  run ! grep -E '(^|[^0-9A-Za-z])R2([^0-9]|$)' "$BODIES/2"
  grep -qx '\*\*Covers:\*\* R2' "$BODIES/3"
  # shellcheck disable=SC2016  # literal backticks and a script's own variables
  grep -qF 'holds the single line `hello`' "$BODIES/3"
}

@test "fixtures: the parent's initial row is never a row for the decision" {
  [ -n "$(log_rows "$(fixture_parent)")" ]
  [ -z "$(decision_rows "$(fixture_parent)" "$VALUE" "$CID")" ]
}

@test "fixtures: nothing in the fixtures can claim the children or block either" {
  file_fixture "$DIR" 20261014-1
  grep -qx "issue edit $U/1 --repo o/r --add-sub-issue $U/2,$U/3" "$LOG"
  run ! grep -E -e '--add-blocked-by|--add-assignee|--add-label|--assignee|--label' "$LOG"
}

@test "file_fixture records each URL as it is filed, so a failure can be cleaned up" {
  FAIL_ON="--add-sub-issue" run file_fixture "$DIR" 20261014-1
  [ "$status" -ne 0 ]
  [ "$(cat "$DIR/parent") $(cat "$DIR/a") $(cat "$DIR/b")" = "$U/1 $U/2 $U/3" ]
}

@test "file_fixture stops at a failed create, before writing the parent's design" {
  FAIL_ON="Name file" run file_fixture "$DIR" 20261014-1
  [ "$status" -ne 0 ]
  [ ! -s "$DIR/a" ]
  run ! grep -q '^issue edit' "$LOG"
}

@test "log_rows and row_state read the table's rows and their state" {
  run log_rows "$(decided_parent new decided)"
  [ "${#lines[@]}" -eq 2 ]
  [ "$(row_state "${lines[1]}")" = decided ]
}

@test "decision_rows matches by value, comment id, or whole ID R2, and not R20" {
  local log='## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| d | D3 | — | changes the greeting to ahoy-20261014-1 | decided |
| d | D4 | — | see #issuecomment-4242 | decided |
| d | R2 | — | anything | decided |
| d | R20 | — | unrelated | decided |
| d | D5 | — | R2, R3 | applied |'
  run decision_rows "$log" "$VALUE" "$CID"
  [ "${#lines[@]}" -eq 4 ]
  run ! grep -q R20 <<< "$output"
}

@test "kill_due needs the new value in the design and a row for it" {
  kill_due "$(decided_parent new decided)" "$VALUE" "$CID"
  run ! kill_due "$(decided_parent old decided)" "$VALUE" "$CID"
  run ! kill_due "$(decided_parent new "")" "$VALUE" "$CID"
}

@test "kill_due does not take the value written below the log for the design" {
  run ! kill_due "$(decided_parent old decided; echo "- 2026-10-14: $VALUE")" "$VALUE" "$CID"
}

@test "iso_before steps back across a minute" {
  [ "$(iso_before 2026-10-14T21:30:02Z 5)" = 2026-10-14T21:29:57Z ]
}

@test "render takes a value literally, & and backslashes included" {
  printf 'a {{K}} b\n' > "$BATS_TEST_TMPDIR/f"
  [ "$(render "$BATS_TEST_TMPDIR/f" 'K=x&y\\z')" = 'a x&y\\z b' ]
}

@test "swept_before_kill: quiet while the row is decided and child B is untouched" {
  run swept_before_kill "$(decided_parent new decided)" "holds \`hello\`" "$VALUE" "$CID"
  [ -z "$output" ]
}

@test "swept_before_kill names child B carrying the value, or the row applied" {
  run swept_before_kill "$(decided_parent new decided)" "holds \`$VALUE\`" "$VALUE" "$CID"
  [ "$output" = "child B already carried the new value" ]
  run swept_before_kill "$(decided_parent new applied)" "holds \`hello\`" "$VALUE" "$CID"
  [ "$output" = "a row for the decision already read applied" ]
}

@test "resume_missing is empty only when all four hold" {
  run resume_missing "$(decided_parent new applied)" "holds \`$VALUE\`" "$VALUE" "$CID" OWN OWN
  [ -z "$output" ]
  run resume_missing "$(decided_parent new decided)" "holds \`hello\`" "$VALUE" "$CID" FOREIGN OWN
  [ "$output" = "child B lacks the new value; not every row for the decision reads applied; child A not re-claimed (FOREIGN)" ]
}

@test "resume_missing does not pass a log with no row for the decision" {
  run resume_missing "$(decided_parent new "")" "holds \`$VALUE\`" "$VALUE" "$CID" OWN OWN
  [ "$output" = "not every row for the decision reads applied" ]
}

@test "kill_tree kills a process and every descendant" {
  bash -c 'bash -c "sleep 30 & sleep 30 & wait" & sleep 30 & wait' 3>&- &
  local top=$! pids i=0
  while :; do
    pids=$(pgrep -P "$top"; for p in $(pgrep -P "$top"); do pgrep -P "$p" || true; done)
    [ "$(wc -w <<< "$pids")" -lt 3 ] && [ "$i" -lt 100 ] || break
    sleep 0.1; i=$((i + 1))
  done
  [ "$(wc -w <<< "$pids")" -ge 3 ]
  kill_tree "$top"
  wait "$top" 2> /dev/null || true
  sleep 0.5
  for p in $top $pids; do run ! kill -0 "$p"; done
}

@test "claim_of asks claim-issue.sh as the given session" {
  SCRIPTS="$BATS_TEST_TMPDIR/scripts"; mkdir -p "$SCRIPTS"
  # shellcheck disable=SC2016  # literal backticks and a script's own variables
  printf '#!/bin/sh\necho "result=$([ "$CLAUDE_CODE_SESSION_ID" = abc ] && echo OWN || echo FOREIGN) claim=x at=y"\n' \
    > "$SCRIPTS/claim-issue.sh"
  chmod +x "$SCRIPTS/claim-issue.sh"
  [ "$(claim_of "$U/2" abc)" = OWN ]
  [ "$(claim_of "$U/2" def)" = FOREIGN ]
}

@test "await_kill_point waits on body edits, re-arms from just before each result's now, and returns once kill_due holds" {
  SCRIPTS="$BATS_TEST_TMPDIR/scripts"; mkdir -p "$SCRIPTS"
  export WATCH_LOG="$BATS_TEST_TMPDIR/watch.log"; : > "$WATCH_LOG"
  cat > "$SCRIPTS/watch-issue.sh" <<'EOF'
#!/usr/bin/env bash
printf 'SETTLE=%s INTERVAL=%s %s\n' "$SETTLE" "$INTERVAL" "$*" >> "$WATCH_LOG"
n=$(wc -l < "$WATCH_LOG" | tr -d ' ')
echo "── re-arm ──"
echo "WINDOW=9 watch-issue.sh o/r 1 --role=author --since=T$n --wake-on=body-edit,close"
echo "result=ACTIVITY issues=1 kinds=body-edit edited=1:x wake-on=body-edit,close now=2026-10-14T21:30:0${n}Z"
EOF
  chmod +x "$SCRIPTS/watch-issue.sh"
  echo "$U/1" > "$DIR/parent"
  export BODY_DIR="$BATS_TEST_TMPDIR"
  decided_parent new "" > "$BODY_DIR/body-1"
  decided_parent new decided > "$BODY_DIR/body-2"
  body_of() { local n; n=$(wc -l < "$WATCH_LOG" | tr -d ' '); cat "$BODY_DIR/body-$n"; }
  sleep 30 3>&- & local orch=$!
  run await_kill_point "$DIR" "$orch" T0 "$VALUE" "$CID"
  kill "$orch"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$WATCH_LOG" | tr -d ' ')" -eq 2 ]
  grep -q '^SETTLE=0 INTERVAL=3 o/r 1 --role=author --wake-on=body-edit,close --since=T0$' "$WATCH_LOG"
  grep -q -- '--wake-on=body-edit,close --since=2026-10-14T21:29:56Z$' "$WATCH_LOG"
}

@test "await_kill_point fails when the orchestrator exits while the watch waits" {
  SCRIPTS="$BATS_TEST_TMPDIR/scripts"; mkdir -p "$SCRIPTS"
  printf '#!/bin/sh\nexec sleep 30\n' > "$SCRIPTS/watch-issue.sh"
  chmod +x "$SCRIPTS/watch-issue.sh"
  echo "$U/1" > "$DIR/parent"
  bash -c 'exit 0' & local orch=$!
  wait "$orch"
  run await_kill_point "$DIR" "$orch" T0 "$VALUE" "$CID"
  [ "$status" -eq 1 ]
  [ "$output" = "the first orchestrator exited before writing the decision" ]
}

@test "await_kill_point fails on a watch error rather than re-arming" {
  SCRIPTS="$BATS_TEST_TMPDIR/scripts"; mkdir -p "$SCRIPTS"
  printf '#!/bin/sh\necho "result=ERROR reason=issue-query now=T"\n' > "$SCRIPTS/watch-issue.sh"
  chmod +x "$SCRIPTS/watch-issue.sh"
  echo "$U/1" > "$DIR/parent"
  sleep 30 3>&- & local orch=$!
  run await_kill_point "$DIR" "$orch" T0 "$VALUE" "$CID"
  kill "$orch"
  [ "$status" -eq 1 ]
  [ "$output" = "the parent's watch failed: result=ERROR reason=issue-query now=T" ]
}

@test "clean_up closes open PRs with their branches, then every filed issue" {
  SCRIPTS="$BATS_TEST_TMPDIR/scripts"; mkdir -p "$SCRIPTS"
  # shellcheck disable=SC2016  # literal backticks and a script's own variables
  printf '#!/bin/sh\n[ "$2" = 3 ] && echo https://github.com/o/r/pull/9\necho "result=OK count=1"\n' \
    > "$SCRIPTS/pr-sources.sh"
  chmod +x "$SCRIPTS/pr-sources.sh"
  echo "$U/1" > "$DIR/parent"; echo "$U/2" > "$DIR/a"; echo "$U/3" > "$DIR/b"
  clean_up "$DIR"
  grep -q '^pr close https://github.com/o/r/pull/9 --delete-branch' "$LOG"
  [ "$(grep -c '^issue close' "$LOG")" -eq 3 ]
}

@test "clean_up leaves a merged or closed PR alone and skips issues never filed" {
  SCRIPTS="$BATS_TEST_TMPDIR/scripts"; mkdir -p "$SCRIPTS"
  printf '#!/bin/sh\necho https://github.com/o/r/pull/9\necho "result=OK count=1"\n' > "$SCRIPTS/pr-sources.sh"
  chmod +x "$SCRIPTS/pr-sources.sh"
  echo "$U/1" > "$DIR/parent"
  PR_STATE=MERGED clean_up "$DIR"
  run ! grep -q '^pr close' "$LOG"
  [ "$(grep -c '^issue close' "$LOG")" -eq 1 ]
}
