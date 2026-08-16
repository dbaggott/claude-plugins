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
# page would otherwise be reported as nothing at all. Returning none of them is
# the case where nothing bounds what is hidden, so the window cannot be cleared.
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

# The page holds the NEWEST comments, so its oldest entry bounds what can be
# hidden: one older than `since` proves the window is fully covered whatever the
# lifetime total says. Keying on the total alone fires on every tick for any
# issue that has ever passed a page — and since the printed re-arm line
# reproduces it, that is a permanent wake loop on exactly the long discussions a
# reviewer watch is pointed at.
@test "a long-but-quiet issue is not read as activity every tick" {
  jq -cn '{data:{repository:{i163:{number:163,state:"OPEN",lastEditedAt:null,
     comments:{totalCount:25,
               nodes:[range(20)|{author:{login:"someone"},
                                 createdAt:"2020-01-01T00:00:00Z",url:"u"}]},
     closedByPullRequestsReferences:{nodes:[]}, timelineItems:{nodes:[]}}}}}' > "$GQL"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"result=IDLE"* ]]
}

# The other side of the same condition: overflowed, and the oldest comment the
# page returned is still inside the window, so something older may be hidden.
@test "an overflowed page whose oldest entry is inside the window is activity" {
  jq -cn '{data:{repository:{i163:{number:163,state:"OPEN",lastEditedAt:null,
     comments:{totalCount:25,
               nodes:[range(20)|{author:{login:"someone"},
                                 createdAt:"2026-06-01T00:00:00Z",url:"u"}]},
     closedByPullRequestsReferences:{nodes:[]}, timelineItems:{nodes:[]}}}}}' > "$GQL"
  INTERVAL=1 SETTLE=1 WINDOW=10 \
    run "$WATCH" o/r 163 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"result=ACTIVITY"* ]]
}

# --- a number that resolves to no issue -----------------------------------------

# The fetch reports it once and the watch has to act on it, or the number is
# re-asked every tick for the life of the watch and the caller is never told
# which of its issues stopped being watched.
@test "an unresolvable issue number is named and leaves the watch set" {
  jq -cn '{data:{repository:{i163:{number:163,state:"OPEN",lastEditedAt:null,
     comments:{totalCount:0,nodes:[]},
     closedByPullRequestsReferences:{nodes:[]}, timelineItems:{nodes:[]}},
     i999:null}}}' > "$GQL"
  INTERVAL=1 WINDOW=6 \
    run "$WATCH" o/r 163 999 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == *"result=IDLE"* ]]
  [[ "${lines[-1]}" == *"missing=999"* ]]
  # And the re-arm carries only the issue that still resolves.
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == *"o/r 163 --role="* ]]
}

# --- the window default is role-dependent --------------------------------------

# lib-poll.sh applies its own WINDOW default at source time, so a role default
# set after the source never fires and both roles get the long window.
@test "the author role gets the short window without being told" {
  jq -cn '{data:{repository:{i163:{number:163,state:"OPEN",lastEditedAt:null,
     comments:{totalCount:0,nodes:[]},
     closedByPullRequestsReferences:{nodes:[]}, timelineItems:{nodes:[]}}}}}' > "$GQL"
  INTERVAL=1000 run "$WATCH" o/r 163 --role=author --since=2026-01-01T00:00:00Z --slug=operator
  [[ "${lines[-1]}" == *"result=IDLE"* ]]
}

# --- a closure must not swallow activity that is still settling ----------------

# The closed-issue check runs before the settle is evaluated, so exiting on it
# drops activity already accumulated on the OTHER watched issues — and the
# re-arm sets `since` past that activity, so it is filtered out for good rather
# than deferred. Both facts ride one line instead.
@test "an issue closing does not drop a pending burst on its siblings" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"api user"*) echo operator; exit 0 ;; esac
t=$(( $(cat "$TICKS" 2>/dev/null || echo 0) + 1 )); echo "$t" > "$TICKS"
if [ "$t" = 1 ]; then st5=OPEN; else st5=CLOSED; fi
jq -cn --arg st5 "$st5" '{data:{repository:{
  i5:{number:5,state:$st5,lastEditedAt:null,comments:{totalCount:0,nodes:[]},
      closedByPullRequestsReferences:{nodes:[]},timelineItems:{nodes:[]}},
  i7:{number:7,state:"OPEN",lastEditedAt:null,
      comments:{totalCount:1,nodes:[{author:{login:"someone"},
                createdAt:"2026-06-01T00:00:00Z",url:"u"}]},
      closedByPullRequestsReferences:{nodes:[]},timelineItems:{nodes:[]}}}}}'
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 SETTLE=30 WINDOW=60 \
    run "$WATCH" o/r 5 7 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "${lines[-1]}" == *"issues=7"* ]]
  [[ "${lines[-1]}" == *"closed=5"* ]]
  # And the closed one leaves the set, or the next arm reports it forever.
  local rearm; rearm=$(printf '%s\n' "$output" | grep -A1 're-arm' | tail -1)
  [[ "$rearm" == *"o/r 7 --role="* ]]
}

# Nothing left to watch: the activity is still owed, but a re-arm line would put
# the watch back on a set that is entirely closed.
@test "a burst reported alongside the last issue closing carries no re-arm" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"api user"*) echo operator; exit 0 ;; esac
t=$(( $(cat "$TICKS" 2>/dev/null || echo 0) + 1 )); echo "$t" > "$TICKS"
if [ "$t" = 1 ]; then st=OPEN; else st=CLOSED; fi
jq -cn --arg st "$st" '{data:{repository:{
  i7:{number:7,state:$st,lastEditedAt:null,
      comments:{totalCount:1,nodes:[{author:{login:"someone"},
                createdAt:"2026-06-01T00:00:00Z",url:"u"}]},
      closedByPullRequestsReferences:{nodes:[]},timelineItems:{nodes:[]}}}}}'
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 SETTLE=30 WINDOW=60 \
    run "$WATCH" o/r 7 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "${lines[-1]}" == *"closed=7"* ]]
  [[ "$output" != *"re-arm"* ]]
}

# --- the ERROR line carries one field per name ---------------------------------

# `reason=` is not the last field on the child's line, so passing everything
# after it through duplicates `now=`.
@test "a refused forge reports one now= field, not two" {
  FORGE=gitlab run "$WATCH" o/r 163 --role=reviewer --slug=bot
  [[ "${lines[-1]}" == "result=ERROR reason=unsupported-forge now="* ]]
  [ "$(grep -o 'now=' <<<"${lines[-1]}" | wc -l | tr -d ' ')" = 1 ]
}

# A closure and a sibling's FIRST activity can land in one tick — they are up to a
# poll interval apart in real time. Answering the closure alone drops that
# activity, and the re-arm sets `since` past it, so no later run reports it
# either. The earlier-tick case is covered above; this is the same loss by a
# different route, and only ordering the branches fixes both.
@test "a closure seen with a sibling's first activity keeps both" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"api user"*) echo operator; exit 0 ;; esac
jq -cn '{data:{repository:{
  i5:{number:5,state:"CLOSED",lastEditedAt:null,comments:{totalCount:0,nodes:[]},
      closedByPullRequestsReferences:{nodes:[]},timelineItems:{nodes:[]}},
  i7:{number:7,state:"OPEN",lastEditedAt:null,
      comments:{totalCount:1,nodes:[{author:{login:"someone"},
                createdAt:"2026-06-01T00:00:00Z",url:"u"}]},
      closedByPullRequestsReferences:{nodes:[]},timelineItems:{nodes:[]}}}}}'
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 SETTLE=1 WINDOW=30 \
    run "$WATCH" o/r 5 7 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=ACTIVITY* ]]
  [[ "${lines[-1]}" == *"issues=7"* ]]
  [[ "${lines[-1]}" == *"closed=5"* ]]
}

# Each missing number leaves the set permanently, so a later one replacing an
# earlier one in the field means the caller is never told about the first.
@test "two issues going missing at different times are both named" {
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"api user"*) echo operator; exit 0 ;; esac
t=$(( $(cat "$TICKS" 2>/dev/null || echo 0) + 1 )); echo "$t" > "$TICKS"
# #9 unresolvable from the start; #10 goes on tick 3.
if [ "$t" -ge 3 ]; then ten=null; else ten='{"number":10,"state":"OPEN","lastEditedAt":null,
  "comments":{"totalCount":0,"nodes":[]},
  "closedByPullRequestsReferences":{"nodes":[]},"timelineItems":{"nodes":[]}}'; fi
jq -cn --argjson ten "$ten" '{data:{repository:{
  i9:null, i10:$ten,
  i11:{number:11,state:"OPEN",lastEditedAt:null,comments:{totalCount:0,nodes:[]},
       closedByPullRequestsReferences:{nodes:[]},timelineItems:{nodes:[]}}}}}'
EOF
  chmod +x "$STUB/gh"
  INTERVAL=1 WINDOW=8 \
    run "$WATCH" o/r 9 10 11 --role=reviewer --since=2026-01-01T00:00:00Z --slug=bot
  [[ "${lines[-1]}" == result=IDLE* ]]
  [[ "${lines[-1]}" == *"missing=9,10"* ]]
}
