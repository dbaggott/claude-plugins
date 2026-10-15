#!/usr/bin/env bats
#
# Tests for the issue body diff. `gh` is stubbed: it serves one page of
# `userContentEdits` per cursor, from JSON each test builds, so pagination runs
# through the real loop rather than a pre-merged answer.

DIFF="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/issue-diff.sh"

T0=2026-10-01T00:00:00Z   # issue created
T1=2026-10-02T00:00:00Z
T2=2026-10-03T00:00:00Z
T3=2026-10-04T00:00:00Z

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export PAGES="$BATS_TEST_TMPDIR/pages"; mkdir -p "$PAGES"
  export ARGV="$BATS_TEST_TMPDIR/argv"; : > "$ARGV"
  export GQL_EXIT="$BATS_TEST_TMPDIR/gql_exit"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ARGV"
cursor=$(printf '%s\n' "$@" | sed -n 's/^cursor=//p')
cat "$PAGES/${cursor:-first}.json" 2>/dev/null
[ -f "$GQL_EXIT" ] && exit 1
exit 0
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

edit() {  # <editedAt> <editor> <body> -> one userContentEdits node
  jq -cn --arg at "$1" --arg ed "$2" --arg b "$3" \
    '{editedAt: $at, deletedAt: null, editor: {login: $ed}, diff: $b}'
}
# <page-name> <next-cursor|""> <current-body> [node...], nodes newest first as the
# API lists them.
page() {
  local name="$1" next="$2" body="$3"; shift 3
  printf '%s\n' "$@" | jq -cs --arg next "$next" --arg body "$body" --arg t0 "$T0" '
    {data: {repository: {issue: {
      createdAt: $t0, body: $body, author: {login: "author"},
      userContentEdits: {
        pageInfo: {hasNextPage: ($next != ""), endCursor: (if $next == "" then null else $next end)},
        nodes: map(select(. != null))}}}}}' > "$PAGES/$name.json"
}
# The common history: created as "a", then three edits.
history() {
  page first "" $'a\nB\nc' \
    "$(edit "$T3" carol $'a\nB\nc')" \
    "$(edit "$T2" bob $'a\nB')" \
    "$(edit "$T1" alice $'a\nb')" \
    "$(edit "$T0" alice 'a')"
}
line() { tail -1 <<<"$1"; }

@test "a normal delta diffs the two snapshots and names both" {
  history
  run "$DIFF" o/r 7 --since="$T1" --until="$T2"
  [ "$status" -eq 0 ]
  [ "$(line "$output")" = "result=OK base=$T1 head=$T2 editors=bob" ]
  [ "$(sed -n 1p <<<"$output")" = "--- base $T1 alice" ]
  [ "$(sed -n 2p <<<"$output")" = "+++ head $T2 bob" ]
  grep -qx -- '-b' <<<"$output"
  grep -qx -- '+B' <<<"$output"
}

@test "a moment between snapshots resolves to the latest one at or before it" {
  history
  run "$DIFF" o/r 7 --since=2026-10-02T12:00:00Z --until=2026-10-03T12:00:00Z
  [ "$(line "$output")" = "result=OK base=$T1 head=$T2 editors=bob" ]
}

@test "--until defaults to the current body, and every editor in between is named" {
  history
  run "$DIFF" o/r 7 --since="$T0"
  [ "$(line "$output")" = "result=OK base=$T0 head=$T3 editors=alice,bob,carol" ]
  grep -qx -- '+c' <<<"$output"
}

@test "the creation snapshot is attributed to the issue author, not its editor" {
  history
  run "$DIFF" o/r 7 --since="$T0" --until="$T1"
  [ "$(sed -n 1p <<<"$output")" = "--- base $T0 author" ]
}

@test "--since before the issue was created has no base and prints the head as additions" {
  history
  run "$DIFF" o/r 7 --since=2026-09-01T00:00:00Z --until="$T0"
  [ "$(line "$output")" = "result=OK base=none head=$T0 editors=author" ]
  [ "$(sed -n 1p <<<"$output")" = "--- base none" ]
  grep -qx -- '+a' <<<"$output"
}

@test "a never-edited issue is one snapshot: its current body at creation" {
  page first "" 'only'
  run "$DIFF" o/r 7 --since="$T1"
  [ "$output" = "result=OK same=true" ]

  run "$DIFF" o/r 7 --since=2026-09-01T00:00:00Z
  [ "$(line "$output")" = "result=OK base=none head=$T0 editors=author" ]
  grep -qx -- '+only' <<<"$output"
}

@test "two edits stamped in the same second resolve to the later one" {
  page first "" 'second' "$(edit "$T1" bob 'second')" "$(edit "$T1" alice 'first')" \
    "$(edit "$T0" author 'zero')"
  run "$DIFF" o/r 7 --since="$T0" --until="$T1"
  [ "$(sed -n 2p <<<"$output")" = "+++ head $T1 bob" ]
  [ "$(line "$output")" = "result=OK base=$T0 head=$T1 editors=alice,bob" ]
}

@test "both moments on one snapshot print nothing but same=true" {
  history
  run "$DIFF" o/r 7 --since="$T1" --until=2026-10-02T23:59:59Z
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK same=true" ]
}

@test "a history past 100 edits is read across pages, passing the cursor" {
  local nodes=() i
  for (( i = 120; i >= 21; i-- )); do
    nodes+=("$(edit "2026-10-05T00:$(printf %02d $((i / 60))):$(printf %02d $((i % 60)))Z" bob "v$i")")
  done
  page first p2 'v120' "${nodes[@]}"
  page p2 "" 'v120' "$(edit "$T1" alice 'v1')" "$(edit "$T0" alice 'v0')"

  run "$DIFF" o/r 7 --since="$T0" --until="$T1"
  [ "$(line "$output")" = "result=OK base=$T0 head=$T1 editors=alice" ]
  grep -q -- 'cursor=p2' "$ARGV"
  [ "$(grep -c -- '-f owner=' "$ARGV")" -eq 2 ]
}

@test "a page whose snapshots total past ARG_MAX still diffs" {
  # 24 snapshots of 50,000 characters, about 1.2 MB, over macOS's 1 MB ARG_MAX
  # and far over Linux's 128 KB cap on any one argument.
  local filler nodes=() i
  filler=$(printf '%050000d' 0)
  for (( i = 23; i >= 1; i-- )); do
    nodes+=("$(edit "2026-10-05T00:00:$(printf %02d "$i")Z" bob "$filler"$'\n'"v$i")")
  done
  page first "" "$filler"$'\n'"v23" "${nodes[@]}" "$(edit "$T0" author "$filler"$'\n'"v0")"
  [ "$(wc -c < "$PAGES/first.json")" -gt 1048576 ]

  run "$DIFF" o/r 7 --since="$T0"
  [ "$status" -eq 0 ]
  [ "$(line "$output")" = "result=OK base=$T0 head=2026-10-05T00:00:23Z editors=bob" ]
  grep -qx -- '+v23' <<<"$output"
}

@test "a history that never reports its last page stops at the cap" {
  page first first 'x' "$(edit "$T1" alice 'x')"
  MAX_PAGES=3 run "$DIFF" o/r 7 --since="$T0"
  [[ "$output" == "result=ERROR reason=history-overflow "* ]]
  [ "$(grep -c -- '-f owner=' "$ARGV")" -eq 3 ]
}

@test "a non-existent issue or repo is not-found, read from stdout despite gh's exit 1" {
  jq -cn '{data: {repository: {issue: null}}, errors: [{type: "NOT_FOUND"}]}' > "$PAGES/first.json"
  touch "$GQL_EXIT"
  run "$DIFF" o/r 999 --since="$T0"
  [ "$status" -eq 0 ]
  [[ "$output" == "result=ERROR reason=not-found "* ]]

  jq -cn '{data: {repository: null}, errors: [{type: "NOT_FOUND"}]}' > "$PAGES/first.json"
  run "$DIFF" o/nope 1 --since="$T0"
  [[ "$output" == "result=ERROR reason=not-found "* ]]
}

@test "no answer at all is issue-query, not not-found" {
  touch "$GQL_EXIT"
  run "$DIFF" o/r 7 --since="$T0"
  [ "$status" -eq 0 ]
  [[ "$output" == "result=ERROR reason=issue-query "* ]]
}

@test "a moment that resolves to a deleted revision is reported, not substituted" {
  history
  jq '.data.repository.issue.userContentEdits.nodes |= map(
        if .editedAt == "'"$T1"'" then .deletedAt = "'"$T3"'" | .diff = null else . end)' \
    "$PAGES/first.json" > "$PAGES/x" && mv "$PAGES/x" "$PAGES/first.json"
  run "$DIFF" o/r 7 --since="$T1" --until="$T2"
  [[ "$output" == "result=ERROR reason=snapshot-deleted "* ]]
}

@test "with --until omitted, the head is the current body even if its revision was deleted" {
  history
  jq '.data.repository.issue.userContentEdits.nodes |= map(
        if .editedAt == "'"$T3"'" then .deletedAt = "'"$T3"'" | .diff = null else . end)' \
    "$PAGES/first.json" > "$PAGES/x" && mv "$PAGES/x" "$PAGES/first.json"
  run "$DIFF" o/r 7 --since="$T2"
  [ "$(line "$output")" = "result=OK base=$T2 head=$T3 editors=carol" ]
  grep -qx -- '+c' <<<"$output"
}

@test "CRLF bodies diff on content, not line endings" {
  page first "" $'a\r\nB' "$(edit "$T1" bob $'a\r\nB')" "$(edit "$T0" author $'a\nb')"
  run "$DIFF" o/r 7 --since="$T0"
  [[ "$output" != *$'\r'* ]]
  grep -qx -- ' a' <<<"$output"
}

@test "the number reaches GraphQL as an Int and owner/repo as Strings" {
  history
  run "$DIFF" 2048/4096 7 --since="$T0"
  grep -q -- '-f owner=2048 -f repo=4096 -F n=7' "$ARGV"
}

@test "bad arguments are refused before any request" {
  local args
  for args in "" "o/r" "o/r 7" "r 7 --since=$T0" "o/r x --since=$T0" \
              "o/r 7 --since=2026-10-01" "o/r 7 --since=$T0 --until=yesterday" \
              "o/r 7 --since=$T2 --until=$T1" "o/r 7 --since=$T0 --extra" \
              "o/t/r 7 --since=$T0" "o/r 7 --since=$T0 --since=$T1" \
              "o/r 7 --since=$T0 --until=$T1 --until=$T2"; do
    # shellcheck disable=SC2086  # word-splitting the case is the point
    run "$DIFF" $args
    [[ "$output" == "result=ERROR reason=bad-args "* ]] || { echo "accepted: $args"; false; }
  done
  [ ! -s "$ARGV" ]
}

@test "a forge other than GitHub is refused" {
  FORGE=gitlab run "$DIFF" o/r 7 --since="$T0"
  [[ "$output" == "result=ERROR reason=unsupported-forge "* ]]
  [ ! -s "$ARGV" ]
}
