#!/usr/bin/env bats
#
# Tests for the issue-side watcher. `gh` and the clock are stubbed, so nothing
# here sleeps for real and every WINDOW/SETTLE below is in synthetic seconds.
#
# Most of these came from watch-pr.bats, where the same behaviours were pinned
# against a `--issue` mode that polled only for linked PRs. Watching an issue's
# conversation is the capability that mode lacked
# (https://github.com/dbaggott/claude-plugins/issues/163); the linked-PR cases
# survive unchanged because that question did not move, only the script it lives
# in did.

WATCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/watch-issue.sh"

load trace-dir
load reap

setup_clock() {
  export CLOCK="$BATS_TEST_TMPDIR/clock"; echo 0 > "$CLOCK"
  cat > "$STUB/date" <<'EOF'
#!/usr/bin/env bash
off=$(cat "$CLOCK" 2>/dev/null || echo 0)
if [ "$1" = "+%s" ]; then echo $(( 1700000000 + off )); else exec /bin/date "$@"; fi
EOF
  cat > "$STUB/sleep" <<'EOF'
#!/usr/bin/env bash
echo $(( $(cat "$CLOCK") + ${1:-0} )) > "$CLOCK"
EOF
  chmod +x "$STUB/date" "$STUB/sleep"
}

setup() {
  contain_traces
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export GQL="$BATS_TEST_TMPDIR/gql.json"
  export GQL_EXIT="$BATS_TEST_TMPDIR/gql_exit"
  export TICKS="$BATS_TEST_TMPDIR/ticks"; echo 0 > "$TICKS"
  setup_clock
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"api user"*) echo operator; exit 0 ;; esac
t=$(( $(cat "$TICKS" 2>/dev/null || echo 0) + 1 )); echo "$t" > "$TICKS"
cat "$GQL"
[ -f "$GQL_EXIT" ] && exit 1
exit 0
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

# One issue's GraphQL node. Defaults are a quiet, open issue.
issue() {  # <n> [comments-json] [linked-json] [state] [lastEditedAt]
  jq -n --arg n "$1" --argjson c "${2:-[]}" --argjson l "${3:-[]}" \
        --arg st "${4:-OPEN}" --arg ed "${5:-}" '
    { number: ($n|tonumber), state: $st,
      lastEditedAt: (if $ed == "" then null else $ed end),
      comments: { totalCount: ($c|length), nodes: $c },
      closedByPullRequestsReferences: { nodes: [] },
      timelineItems: { nodes: ($l | map({source: {url: .}})) } }'
}

# Assemble the aliased response the batched query returns.
repo() {  # <issue-json>...
  local acc='{}' i
  for i in "$@"; do
    acc=$(jq -c --argjson n "$i" '. + {("i" + ($n.number|tostring)): $n}' <<<"$acc")
  done
  jq -cn --argjson r "$acc" '{data:{repository:$r}}' > "$GQL"
}

comment() {  # <login> <iso>
  jq -cn --arg a "$1" --arg t "$2" '[{author:{login:$a}, createdAt:$t, url:"u"}]'
}

@test "a comment from someone else wakes the watch" {
  repo "$(issue 163 "$(comment human 2026-01-02T00:00:00Z)")"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == "result=ACTIVITY issues=163 kinds=comment"* ]]
}

@test "a comment the watch itself posted wakes nothing" {
  repo "$(issue 163 "$(comment bot 2026-01-02T00:00:00Z)")"
  INTERVAL=1 SETTLE=1 WINDOW=4 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=IDLE* ]]
}

# The operator's login is a substring of the bot's, so an author-side watch
# matching loosely drops every reviewer comment it exists to catch — and reports
# a quiet issue while seeing all of them.
@test "the exclusion is an exact login, not a substring" {
  repo "$(issue 163 "$(comment agent-reviewer-operator 2026-01-02T00:00:00Z)")"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=author --since=2026-01-01T00:00:00Z --slug=operator
  [[ "${lines[-1]}" == *"result=ACTIVITY"* ]]
}

@test "a comment older than since wakes nothing" {
  repo "$(issue 163 "$(comment human 2025-01-01T00:00:00Z)")"
  INTERVAL=1 SETTLE=1 WINDOW=4 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=IDLE* ]]
}

@test "a body edit after since wakes the watch" {
  repo "$(issue 163 '[]' '[]' OPEN 2026-01-02T00:00:00Z)"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"kinds=body-edit"* ]]
}

# A body that has never been edited reads as null, which is a reading — "the body
# has not moved" — and must not be treated as a timestamp that beats `since`.
@test "a body that has never been edited wakes nothing" {
  repo "$(issue 163)"
  INTERVAL=1 SETTLE=1 WINDOW=4 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=IDLE* ]]
}

@test "a linked PR appearing wakes the watch" {
  repo "$(issue 163 '[]' '["https://github.com/o/r/pull/9"]')"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"kinds=linked-pr"* ]]
}

@test "an already-triaged PR does not re-wake the watch" {
  repo "$(issue 163 '[]' '["https://github.com/o/r/pull/9"]')"
  INTERVAL=1 SETTLE=1 WINDOW=4 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot \
      --exclude=https://github.com/o/r/pull/9
  [[ "${lines[-1]}" == result=IDLE* ]]
}

@test "a fresh PR alongside an excluded one still wakes the watch" {
  repo "$(issue 163 '[]' '["https://github.com/o/r/pull/9","https://github.com/o/r/pull/10"]')"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot \
      --exclude=https://github.com/o/r/pull/9
  [[ "${lines[-1]}" == *"kinds=linked-pr"* ]]
}

# `grep -vxF` matches whole lines, so an entry written after a comma with a
# space can never equal a URL the poll produces — and the flag fails open,
# turning the watch into the hot loop it exists to prevent, with no diagnostic.
@test "exclusion entries survive whitespace after the comma" {
  repo "$(issue 163 '[]' '["https://github.com/o/r/pull/9"]')"
  INTERVAL=1 SETTLE=1 WINDOW=4 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot \
      --exclude="https://github.com/o/r/pull/8, https://github.com/o/r/pull/9"
  [[ "${lines[-1]}" == result=IDLE* ]]
}

@test "the PRs that woke the watch are folded into the re-arm line" {
  repo "$(issue 163 '[]' '["https://github.com/o/r/pull/9"]')"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "$output" == *"── re-arm ──"* ]]
  [[ "$output" == *"--exclude=https://github.com/o/r/pull/9"* ]]
}

@test "an issue closing stops the watch" {
  repo "$(issue 163 '[]' '[]' CLOSED)"
  INTERVAL=1 WINDOW=4 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == "result=CLOSED issues=163"* ]]
}

@test "several issues are watched in one query, and the hit names which" {
  repo "$(issue 163)" "$(issue 164 "$(comment human 2026-01-02T00:00:00Z)")"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 164 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"issues=164"* ]]
}

# One tick per poll however many issues are watched — the property that makes a
# batch worth the aliasing.
@test "watching several issues still costs one call per tick" {
  repo "$(issue 163)" "$(issue 164)" "$(issue 165)"
  INTERVAL=1 WINDOW=3 \
    run "$WATCH" o/r 163 164 165 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [ "$(cat "$TICKS")" -le 4 ]
}

# GraphQL answers an unresolvable alias with null and valid data for the rest,
# while `gh` exits 1. Reading the status alone loses the issues that answered.
@test "one bad issue number does not blind the watch" {
  jq -cn --argjson good "$(issue 163 "$(comment human 2026-01-02T00:00:00Z)")" \
    '{data:{repository:{i163:$good, i999:null}},
      errors:[{type:"NOT_FOUND",path:["repository","i999"]}]}' > "$GQL"
  : > "$GQL_EXIT"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 999 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"result=ACTIVITY"* ]]
  [[ "${lines[-1]}" == *"issues=163"* ]]
}

@test "every issue unresolvable is an error rather than a quiet watch" {
  echo '{"data":{"repository":{"i999":null}}}' > "$GQL"
  : > "$GQL_EXIT"
  INTERVAL=1 WINDOW=30 FAIL_MAX=2 FAIL_MIN_SECONDS=0 \
    run "$WATCH" o/r 999 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"result=ERROR reason=issue-query"* ]]
}

# A page that overflowed hides its oldest comments, so a burst larger than the
# page would otherwise be reported as nothing at all.
@test "a comment page that overflowed is treated as activity" {
  jq -cn '{data:{repository:{i163:{number:163,state:"OPEN",lastEditedAt:null,
     comments:{totalCount:99, nodes:[]},
     closedByPullRequestsReferences:{nodes:[]}, timelineItems:{nodes:[]}}}}}' > "$GQL"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"result=ACTIVITY"* ]]
}

@test "a payload that stops parsing reports ERROR rather than a quiet watch" {
  echo 'not json at all' > "$GQL"
  INTERVAL=1 WINDOW=30 FAIL_MAX=2 FAIL_MIN_SECONDS=0 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"result=ERROR"* ]]
}

@test "a missing role is refused rather than assumed" {
  repo "$(issue 163)"
  run "$WATCH" o/r 163 --since=2026-01-01T00:00:00Z --slug=bot
  [[ "$output" == *"reason=bad-args"* ]]
}

@test "an empty slug is refused rather than excluding nobody" {
  repo "$(issue 163)"
  run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=
  [[ "$output" == *"reason=bad-args"* ]]
}

@test "a non-numeric issue number is refused" {
  repo "$(issue 163)"
  run "$WATCH" o/r abc --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "$output" == *"reason=bad-args"* ]]
}

@test "an unrecognised flag is refused rather than ignored" {
  repo "$(issue 163)"
  run "$WATCH" o/r 163 --role=reviewer --slug=bot --nope
  [[ "$output" == *"reason=bad-args"* ]]
}

@test "an author role derives its own login when none is given" {
  repo "$(issue 163 "$(comment human 2026-01-02T00:00:00Z)")"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=author --since=2026-01-01T00:00:00Z
  [[ "${lines[-1]}" == *"result=ACTIVITY"* ]]
}

@test "a quiet watch carries its re-arm line" {
  repo "$(issue 163)"
  INTERVAL=1 WINDOW=3 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "$output" == *"── re-arm ──"* ]]
  [[ "$output" == *"--since=20"* ]]
}

# A comment claiming "fixed" against a body that has never moved is definitionally
# unsupported, and that check is the reason the stamp rides along: making the
# caller fetch it separately is the thing one batched query exists to avoid.
@test "a reported hit carries each issue's body-edit stamp" {
  repo "$(issue 163 "$(comment human 2026-01-02T00:00:00Z)" '[]' OPEN 2026-01-03T00:00:00Z)"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"edited=163:2026-01-03T00:00:00Z"* ]]
}

# Null is a reading — "the body has not moved" — and a caller comparing it
# against a timestamp must not take it for missing information, which is exactly
# the case the check exists to catch.
@test "a body never edited reports none rather than an empty field" {
  repo "$(issue 163 "$(comment human 2026-01-02T00:00:00Z)")"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"edited=163:none"* ]]
}

# The closed issue leaves the watch set. Re-arming with it still in there reports
# the same closure on the next tick, forever — one model wake per iteration — and
# the header tells callers to re-arm from this line.
@test "a closed issue is dropped from the re-arm line" {
  repo "$(issue 163 '[]' '[]' CLOSED)" "$(issue 164)"
  INTERVAL=1 WINDOW=4 \
    run "$WATCH" o/r 163 164 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == "result=CLOSED issues=163"* ]]
  [[ "$output" == *"── re-arm ──"* ]]
  [[ "$output" == *"o/r 164 --role"* ]]
  [[ "$output" != *"o/r 163"* ]]
}

@test "the last issue closing leaves nothing to re-arm" {
  repo "$(issue 163 '[]' '[]' CLOSED)"
  INTERVAL=1 WINDOW=4 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == "result=CLOSED issues=163"* ]]
  [[ "$output" != *"── re-arm ──"* ]]
}

# Every new PR is folded into the exclusion the re-arm carries, so an issue whose
# PR went unreported never gets another chance to report it.
@test "every issue with a new linked PR is reported, not just the first" {
  repo "$(issue 163 '[]' '["https://github.com/o/r/pull/9"]')" \
       "$(issue 164 '[]' '["https://github.com/o/r/pull/10"]')"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 164 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"issues=163,164"* ]]
}
