#!/usr/bin/env bats
#
# Tests for the stage lookup. `gh` is stubbed on PATH and replays a fixture from
# tests/fixtures/issue-stage/, keyed by issue-stage-calls.bash, so the
# composition runs end to end: issue-stage.sh's own query plus every call the
# sub-scripts it composes make. capture-issue-stage.sh records the fixtures; the
# ones whose stage no live issue is in list their edits in `_edited`.

STAGE="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/issue-stage.sh"
FIX="${BATS_TEST_DIRNAME}/fixtures/issue-stage"
R=dbaggott/claude-plugins
SLUG=--slug=agent-reviewer-dbaggott

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export FIXTURE="$BATS_TEST_TMPDIR/fixture.json"
  export UNRECORDED="$BATS_TEST_TMPDIR/unrecorded"; : > "$UNRECORDED"
  export CALLS_LIB="${BATS_TEST_DIRNAME}/fixtures/issue-stage-calls.bash"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
. "$CALLS_LIB"
key=$(issue_stage_call_key "$@")
jq -e --arg k "$key" '.calls | has($k)' "$FIXTURE" >/dev/null || {
  echo "$key" >> "$UNRECORDED"; exit 1; }
jq -j --arg k "$key" '.calls[$k].out' "$FIXTURE"
exit "$(jq -r --arg k "$key" '.calls[$k].exit' "$FIXTURE")"
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  unset CLAUDE_CODE_SESSION_ID
  # No reviewer config, so only --slug names the bot.
  export DNBG_REVIEWER_CONFIG_DIR="$BATS_TEST_TMPDIR/no-config"
}

use() { cp "$FIX/$1.json" "$FIXTURE"; }
# <key> <jq filter> -> the recorded answer to <key>, rewritten
edit() {
  local t; t=$(mktemp "$BATS_TEST_TMPDIR/fx.XXXXXX")
  jq --arg k "$1" ".calls[\$k].out |= (fromjson | $2 | tojson)" "$FIXTURE" > "$t" && mv "$t" "$FIXTURE"
}
# The run read only answers the fixture holds.
all_recorded() { [ ! -s "$UNRECORDED" ] || { cat "$UNRECORDED"; false; }; }

@test "a plain issue with no claim, PR or verdict is ready to resolve" {
  use plain-ready
  run "$STAGE" $R 407 $SLUG
  [ "$status" -eq 0 ]
  [ "$output" = "result=OK kind=plain stage=ready next=resolve evidence=claim=none prs=none verdict=none" ]
  all_recorded
}

@test "a tracking issue with no children and the acceptance row is ready to decompose" {
  use tracking-accepted
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=accepted next=decompose evidence=children=0 acceptance_row=yes" ]
  all_recorded
}

@test "a tracking issue whose child lacks a READY verdict is in set review" {
  use tracking-set-review
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=set-review next=review-spec evidence=children=12 open=12 verdict=READY" ]
  all_recorded
}

@test "a tracking issue whose open children all read READY is ready to orchestrate" {
  use tracking-ready
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=ready next=orchestrate evidence=children=12 open=12 verdict=READY" ]
  all_recorded
}

@test "a child names its parent's prompt and stage" {
  use child-in-project
  run "$STAGE" $R 224 $SLUG
  [ "$output" = "result=OK kind=child stage=in-project next=orchestrate evidence=parent=https://github.com/$R/issues/223 parent_stage=ready" ]
  all_recorded
}

@test "a closed issue is closed whatever its kind" {
  use tracking-closed
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=closed next=none evidence=state=closed" ]
  all_recorded
}

@test "a missing issue is the not-found error" {
  use missing
  run "$STAGE" $R 99999 $SLUG
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^result=ERROR\ reason=not-found\ now=[0-9T:Z-]+$ ]]
}

@test "a claim on a tracking issue or on any open child means it is being orchestrated" {
  use tracking-ready
  edit "claim:$R#223" '.data.repository.issue.assignees.nodes = [{login: "someone"}]'
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=orchestrating next=orchestrate evidence=claim=foreign children=12 open=12" ]

  use tracking-ready
  edit "set:$R#223" '.data.repository.issue.subIssues.nodes[3].labels.nodes += [{name: "assigned:other"}]
                     | .data.repository.issue.subIssues.nodes[3].labels.totalCount += 1'
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=orchestrating next=orchestrate evidence=claim=none children=12 open=12" ]
}

@test "every child closed is the closeout, with no closing PR yet" {
  use tracking-ready
  edit "set:$R#223" '.data.repository.issue.subIssues.nodes |= map(.state = "CLOSED")'
  jq '.calls += {"closing:'$R'#223": {out: "{\"closedByPullRequestsReferences\":[]}", exit: 0},
                 "timeline:'$R'#223": {out: "[[]]", exit: 0},
                 "search:'$R'#223": {out: "[]", exit: 0}}' "$FIXTURE" > "$FIXTURE.new" && mv "$FIXTURE.new" "$FIXTURE"
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=closeout next=orchestrate evidence=children=12 open=0 prs=none" ]
}

# <issue key suffix> <pr url> <state> -> the PR sources answer one PR that closes the issue
closing_pr() {
  jq --arg i "$R#$1" --arg u "$2" --arg s "$3" '.calls += {
      ("closing:" + $i): {out: ({closedByPullRequestsReferences: [{url: $u}]} | tojson), exit: 0},
      ("timeline:" + $i): {out: "[[]]", exit: 0},
      ("search:" + $i): {out: ([{url: $u}] | tojson), exit: 0},
      ("prview:" + $u): {out: ({title: "t", headRefName: "b", closingIssuesReferences: []} | tojson), exit: 0},
      ("prstate:" + $u): {out: $s, exit: 0}}' "$FIXTURE" > "$FIXTURE.new" && mv "$FIXTURE.new" "$FIXTURE"
}

@test "every child closed with the closing PR open is the closeout PR to merge" {
  use tracking-ready
  edit "set:$R#223" '.data.repository.issue.subIssues.nodes |= map(.state = "CLOSED")'
  closing_pr 223 "https://github.com/$R/pull/500" OPEN
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=closeout next=merge-closeout evidence=children=12 open=0 prs=https://github.com/$R/pull/500" ]
}

@test "an open PR that closes a plain issue puts it in progress; a merged one does not" {
  use plain-ready
  closing_pr 407 "https://github.com/$R/pull/500" OPEN
  run "$STAGE" $R 407 $SLUG
  [ "$output" = "result=OK kind=plain stage=in-progress next=resolve evidence=claim=none prs=https://github.com/$R/pull/500" ]

  use plain-ready
  closing_pr 407 "https://github.com/$R/pull/500" MERGED
  run "$STAGE" $R 407 $SLUG
  [ "$output" = "result=OK kind=plain stage=ready next=resolve evidence=claim=none prs=none verdict=none" ]
}

@test "a childless tracking issue without the row is in design review, or a draft before any verdict" {
  use tracking-accepted
  edit "stage:$R#223" '.data.repository.issue.body |= split("\n")[0]'
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=design-review next=review-spec evidence=children=0 acceptance_row=no verdict=READY" ]

  edit "set:$R#223" '.data.repository.issue |= ((.oldest.nodes, .newest.nodes) |= [])'
  run "$STAGE" $R 223 $SLUG
  [ "$output" = "result=OK kind=tracking stage=design-draft next=review-spec evidence=children=0 acceptance_row=no verdict=none" ]
}

@test "a proposed acceptance row is not acceptance" {
  use tracking-accepted
  edit "stage:$R#223" '.data.repository.issue.body |= sub("\\| decided \\|$"; "| proposed |")'
  run "$STAGE" $R 223 $SLUG
  [[ "$output" == *" stage=design-review "*"acceptance_row=no"* ]]
}

@test "a plain issue with a claim is in progress" {
  use plain-ready
  edit "claim:$R#407" '.data.repository.issue.labels.nodes += [{name: "assigned:agent-session"}]'
  run "$STAGE" $R 407 $SLUG
  [ "$output" = "result=OK kind=plain stage=in-progress next=resolve evidence=claim=foreign prs=none" ]
}

@test "a verdict that is not READY puts a plain issue in spec review" {
  use plain-ready
  edit "set:$R#407" '.data.repository.issue.newest.nodes += [{author: {login: "agent-reviewer-dbaggott[bot]"},
                       body: "**Spec review, round 1: CHANGES REQUESTED**"}]
                     | .data.repository.issue.newest.totalCount += 1'
  run "$STAGE" $R 407 $SLUG
  [ "$output" = "result=OK kind=plain stage=spec-review next=review-spec evidence=claim=none prs=none verdict=CHANGES-REQUESTED" ]
}

@test "with no slug and no reviewer config a verdict-dependent stage is unknown, not ready" {
  use plain-ready
  run "$STAGE" $R 407
  [ "$output" = "result=OK kind=plain stage=unknown next=unknown evidence=claim=none prs=none verdict=unknown-verdict" ]

  use tracking-ready
  run "$STAGE" $R 223
  [ "$output" = "result=OK kind=tracking stage=unknown next=unknown evidence=children=12 open=12 verdict=unknown-verdict" ]
}

@test "the reviewer config supplies the slug when --slug is absent" {
  mkdir -p "$DNBG_REVIEWER_CONFIG_DIR"
  echo '{"slug": "agent-reviewer-dbaggott"}' > "$DNBG_REVIEWER_CONFIG_DIR/config.json"
  use tracking-ready
  run "$STAGE" $R 223
  [ "$output" = "result=OK kind=tracking stage=ready next=orchestrate evidence=children=12 open=12 verdict=READY" ]
}

@test "a PR source that failed is an error, not an issue with no PRs" {
  use plain-ready
  jq '.calls["search:'$R'#407"].exit = 1' "$FIXTURE" > "$FIXTURE.new" && mv "$FIXTURE.new" "$FIXTURE"
  run "$STAGE" $R 407 $SLUG
  [[ "$output" =~ ^result=ERROR\ reason=issue-query\  ]]
}

@test "bad arguments are refused before any call" {
  use missing
  for args in "" "$R" "o 1" "$R x" "$R 1 2" "$R 1 --bogus"; do
    # shellcheck disable=SC2086  # each case is a word list
    run "$STAGE" $args
    [[ "$output" =~ ^result=ERROR\ reason=bad-args\  ]] || { echo "args: $args -> $output"; false; }
  done
  [ ! -s "$UNRECORDED" ]
}
