#!/usr/bin/env bats
#
# Tests for the stack script. `gh` is stubbed on PATH and told apart by
# subcommand and path: the stack lookup answers from a file per PR, the two
# POSTs answer from a queue of HTTP statuses so a 409 followed by a 200 can be
# played, and the PR and repo reads answer from a file each.

STACK="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/stack-prs.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  # One file per PR number, the list `GET …/stacks?pull_request=<n>` returns;
  # a PR with none is in no stack.
  export STACKS="$BATS_TEST_TMPDIR/stacks"; mkdir -p "$STACKS"
  export FAIL_STACKS="$BATS_TEST_TMPDIR/fail_stacks"
  # The HTTP statuses the next `add` calls answer, one per line, popped in order.
  export ADD_STATUSES="$BATS_TEST_TMPDIR/add_statuses"; : > "$ADD_STATUSES"
  export FAIL_CREATE="$BATS_TEST_TMPDIR/fail_create"
  export BASE_REF="$BATS_TEST_TMPDIR/base_ref"; echo main > "$BASE_REF"
  export DEFAULT_BRANCH="$BATS_TEST_TMPDIR/default_branch"; echo main > "$DEFAULT_BRANCH"
  export STACK_RETRY_WAIT=0
  cat > "$STUB/gh" <<'EOF2'
#!/usr/bin/env bash
q="$*"; echo "$q" >> "$CALLS"
case "$q" in
  "api repos/"*"/stacks?pull_request="*)
    [ -f "$FAIL_STACKS" ] && exit 1
    f="$STACKS/${q##*=}"
    if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
  "api -X POST repos/"*"/stacks/"*"/add "*)
    status=$(head -1 "$ADD_STATUSES"); sed -i.bak 1d "$ADD_STATUSES"
    case "${status:-200}" in
      200) echo '{"number":3,"pull_requests":[]}' ;;
      *) printf '{"message":"refused","status":"%s"}\n' "$status"; echo "gh: refused (HTTP $status)" >&2; exit 1 ;;
    esac ;;
  "api -X POST repos/"*"/stacks "*)
    [ -f "$FAIL_CREATE" ] && exit 1
    case "$q" in *--jq*) echo 7 ;; *) echo '{"number":7}' ;; esac ;;
  "pr view "*)
    [ -s "$BASE_REF" ] || exit 1
    cat "$BASE_REF" ;;
  "repo view "*)
    [ -s "$DEFAULT_BRANCH" ] || exit 1
    cat "$DEFAULT_BRANCH" ;;
  *) exit 1 ;;
esac
EOF2
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

# stack <pr> <number> <entry>... writes the list the lookup for <pr> returns,
# one stack holding the entries bottom to top. An entry is `<n>:open`,
# `<n>:merged` or `<n>:closed`.
stack() {
  local pr="$1" n="$2"; shift 2
  local prs="" e num st
  for e in "$@"; do
    num="${e%%:*}"; st="${e##*:}"
    case "$st" in
      open)   prs="$prs{\"number\":$num,\"state\":\"open\",\"merged_at\":null}," ;;
      merged) prs="$prs{\"number\":$num,\"state\":\"closed\",\"merged_at\":\"2026-01-01T00:00:00Z\"}," ;;
      closed) prs="$prs{\"number\":$num,\"state\":\"closed\",\"merged_at\":null}," ;;
    esac
  done
  printf '[{"number":%s,"pull_requests":[%s]}]' "$n" "${prs%,}" > "$STACKS/$pr"
}

posts() { grep -c '^api -X POST' "$CALLS" || true; }

# --- arguments and the forge ---------------------------------------------------

@test "bad arguments are refused before any call" {
  run "$STACK"; [ "$output" = "result=ERROR reason=bad-args" ]
  run "$STACK" o/r; [ "$output" = "result=ERROR reason=bad-args" ]
  run "$STACK" o 4; [ "$output" = "result=ERROR reason=bad-args" ]
  run "$STACK" o/r x; [ "$output" = "result=ERROR reason=bad-args" ]
  run "$STACK" o/r 4 --onto=; [ "$output" = "result=ERROR reason=bad-args" ]
  run "$STACK" o/r 4 --onto=4; [ "$output" = "result=ERROR reason=bad-args" ]
  run "$STACK" o/r 4 --base=2; [ "$output" = "result=ERROR reason=bad-args" ]
  run "$STACK" o/r 4 --onto=2 extra; [ "$output" = "result=ERROR reason=bad-args" ]
  [ ! -s "$CALLS" ]
}

@test "another forge is refused in both modes" {
  FORGE=gitlab run "$STACK" o/r 4
  [ "$output" = "result=ERROR reason=unsupported-forge" ]
  FORGE=gitlab run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=unsupported-forge" ]
  [ ! -s "$CALLS" ]
}

# --- read mode -----------------------------------------------------------------

@test "a PR in no stack reads none on every field" {
  run "$STACK" o/r 4
  [ "$output" = "result=OK stack=none below=none above=none" ]
}

@test "below and above are the open PRs on each side, merged ones left out" {
  stack 4 3 1:open 2:merged 4:open 6:open 8:closed 9:open
  run "$STACK" o/r 4
  [ "$output" = "result=OK stack=3 below=1 above=6,9" ]
}

@test "the bottom and the top of a stack read none on the empty side" {
  stack 1 3 1:open 2:open
  run "$STACK" o/r 1
  [ "$output" = "result=OK stack=3 below=none above=2" ]
  stack 2 3 1:open 2:open
  run "$STACK" o/r 2
  [ "$output" = "result=OK stack=3 below=1 above=none" ]
}

@test "a lookup that fails, is not a list, or omits the PR reads stack-read" {
  touch "$FAIL_STACKS"
  run "$STACK" o/r 4
  [ "$output" = "result=ERROR reason=stack-read" ]
  rm "$FAIL_STACKS"; echo '{"message":"nope"}' > "$STACKS/4"
  run "$STACK" o/r 4
  [ "$output" = "result=ERROR reason=stack-read" ]
  stack 4 3 1:open 2:open
  run "$STACK" o/r 4
  [ "$output" = "result=ERROR reason=stack-read" ]
}

# --- form mode -----------------------------------------------------------------

@test "a base PR in a stack gets the PR added above it" {
  stack 2 3 1:open 2:open
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=OK stack=3" ]
  grep -qx 'api -X POST repos/o/r/stacks/3/add -F pull_requests\[\]=4' "$CALLS"
  [ "$(posts)" -eq 1 ]
}

@test "a 409 on add is retried once, and a 200 after it is OK" {
  stack 2 3 1:open 2:open
  printf '409\n200\n' > "$ADD_STATUSES"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=OK stack=3" ]
  [ "$(posts)" -eq 2 ]
}

@test "a second 409 is stack-add, and any other refusal is stack-add at once" {
  stack 2 3 1:open 2:open
  printf '409\n409\n' > "$ADD_STATUSES"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=stack-add" ]
  [ "$(posts)" -eq 2 ]
  : > "$CALLS"; printf '422\n' > "$ADD_STATUSES"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=stack-add" ]
  [ "$(posts)" -eq 1 ]
}

@test "a base PR in no stack on the default branch starts a stack of the two" {
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=OK stack=7" ]
  grep -q '^api -X POST repos/o/r/stacks -F pull_requests\[\]=2 -F pull_requests\[\]=4' "$CALLS"
  [ "$(posts)" -eq 1 ]
}

@test "a base PR in no stack on another branch is stack-create with nothing formed" {
  echo feature > "$BASE_REF"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=stack-create" ]
  [ "$(posts)" -eq 0 ]
}

@test "a base PR or default branch that cannot be read is pr-view" {
  : > "$BASE_REF"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=pr-view" ]
  echo main > "$BASE_REF"; : > "$DEFAULT_BRANCH"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=pr-view" ]
  [ "$(posts)" -eq 0 ]
}

@test "a refused create is stack-create" {
  touch "$FAIL_CREATE"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=stack-create" ]
}

@test "a failed stack lookup in form mode is stack-read, before any write" {
  touch "$FAIL_STACKS"
  run "$STACK" o/r 4 --onto=2
  [ "$output" = "result=ERROR reason=stack-read" ]
  [ "$(posts)" -eq 0 ]
}
