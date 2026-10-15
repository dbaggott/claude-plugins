#!/usr/bin/env bash
#
# Restart eval (R26 of https://github.com/dbaggott/claude-plugins/issues/223):
# kill the orchestrator after a design decision reaches `decided` and before its
# sweep, start a fresh one, and check that the fresh one finishes the sweep.
#
# Each run, against the live REPO:
#
#   1. Files a scratch tracking issue with two children from fixtures/. Child B
#      covers R2 and states its value, `hello`; child A never cites R2.
#   2. Starts an orchestrator, a headless `claude -p` on the parent's URL, in a
#      fresh clone of REPO.
#   3. Once both children carry the orchestrator's claim, posts the decision as
#      an operator comment on the parent, "Decision: R2 changes to …", naming a
#      new value unique to the run. That is the path D4 prescribes: the
#      orchestrator, not the operator, turns it into a `decided` row and edits
#      the design.
#   4. Watches the parent with watch-issue.sh and, on the body edit that shows
#      both the new value in the design and a row for the decision, kills the
#      orchestrator and every process under it.
#   5. Starts a fresh orchestrator on the parent's URL, in a clone of its own,
#      so nothing it resumes from can be local state, with Q9's confirmation
#      that the predecessor is gone given in its prompt.
#   6. Passes when child B's body carries the new value, every row for the
#      decision reads `applied`, and both children carry the fresh orchestrator's
#      claim.
#
# INCONCLUSIVE. The kill fires on a poll, so a fast sweep can finish first. When,
# right after the kill, child B already carries the new value or a row for the
# decision reads `applied`, the run did not kill between `decided` and the sweep
# and tested nothing; it is reported as INCONCLUSIVE, not as a pass or a fail.
#
# A row is "for the decision" when it carries the new value, the decision
# comment's id, or the ID R2.
#
# Run by hand, not in CI. Every run spends model calls on two orchestrators and
# the authors and reviewers they dispatch, and writes issues, comments, branches
# and PRs to REPO:
#
#   tests/evals/restart/run.sh
#   RUNS=3 MODEL=sonnet tests/evals/restart/run.sh
#
# Prints one line per run, PASS, FAIL or INCONCLUSIVE with the parent's URL, then
# the counts. Exits 0 only when every run passed. Each run's orchestrator
# transcripts and its clone are kept under the printed artifacts directory
# (EVAL_OUT to choose it). Unless KEEP=1, the run's PRs and issues are closed
# when it ends; the issues' threads stay readable as the run's evidence.
#
# The tree's plugin is loaded as in tests/evals/delegated-mode/run.sh:
# `--plugin-dir <tree>/dnbg-workflow` with `--setting-sources ""`. Unlike that
# eval, gh is real here: the orchestrators run on the operator's own gh login,
# since what is under test is their behaviour against GitHub.
#
# Environment: REPO (default dbaggott/dnbg-watch-testbed), RUNS (default 1),
# MODEL (default: the CLI's), MAX_BUDGET_USD (per orchestrator, optional),
# CLAIM_TIMEOUT, KILL_TIMEOUT, RESUME_TIMEOUT (seconds for each phase; defaults
# 900, 1800, 2700), KEEP, EVAL_OUT, CLAUDE_BIN (default `claude`).

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
SCRIPTS="$TREE/dnbg-workflow/scripts"
REPO=${REPO:-dbaggott/dnbg-watch-testbed}

# shellcheck source=../render.sh
. "$HERE/../render.sh"

# <body> -> the lines above the decision log: the design, without the rows
design_text() {
  awk '/^## Decision log/ { exit } { print }' <<< "$1"
}

# <body> -> the decision log's table rows, header and separator dropped
log_rows() {
  awk '/^## / { in_log = ($0 ~ /^## Decision log/); next }
       in_log && /^\|/ && !/^\| *Date *\|/ && !/^\| *-/ { print }' <<< "$1"
}

# <body> <value> <comment-id> -> the rows for the decision
decision_rows() {
  log_rows "$1" | grep -E -e "$2" -e "issuecomment-$3" -e '(^|[^0-9A-Za-z])R2([^0-9]|$)' || true
}

# <row> -> its State cell
row_state() {
  awk -F'|' '{ s = $(NF - 1); gsub(/^ +| +$/, "", s); print s }' <<< "$1"
}

# <rows> -> 0 when every row reads `applied`, and there is at least one
all_applied() {
  local row
  [ -n "$1" ] || return 1
  while IFS= read -r row; do
    [ "$(row_state "$row")" = applied ] || return 1
  done <<< "$1"
}

# <rows> -> 0 when any row reads `applied`
any_applied() {
  local row
  while IFS= read -r row; do
    [ -n "$row" ] && [ "$(row_state "$row")" = applied ] && return 0
  done <<< "$1"
  return 1
}

# <parent-body> <value> <comment-id> -> 0 once the orchestrator has written the
# decision: the new value in the design and a row for it in the log
kill_due() {
  grep -qF -- "$2" <<< "$(design_text "$1")" && [ -n "$(decision_rows "$1" "$2" "$3")" ]
}

# <parent-body> <child-b-body> <value> <comment-id> -> why the sweep had already
# run when the kill landed, or nothing when it had not
swept_before_kill() {
  if grep -qF -- "$3" <<< "$2"; then echo "child B already carried the new value"
  elif any_applied "$(decision_rows "$1" "$3" "$4")"; then echo "a row for the decision already read applied"
  fi
}

# <parent-body> <child-b-body> <value> <comment-id> <a-claim> <b-claim> -> what
# the fresh orchestrator has yet to do, or nothing once it has done all of it.
# Each claim argument is claim-issue.sh's verdict for the fresh session's id.
resume_missing() {
  local missing=()
  grep -qF -- "$3" <<< "$2" || missing+=("child B lacks the new value")
  all_applied "$(decision_rows "$1" "$3" "$4")" || missing+=("not every row for the decision reads applied")
  [ "$5" = OWN ] || missing+=("child A not re-claimed ($5)")
  [ "$6" = OWN ] || missing+=("child B not re-claimed ($6)")
  [ "${#missing[@]}" -gt 0 ] || return 0
  local joined
  joined=$(printf '%s; ' "${missing[@]}")
  echo "${joined%; }"
}

# <pid> -> stops it and everything under it. Each process is stopped before its
# children are listed, so none can spawn a process the kill misses, and is
# killed after them.
kill_tree() {
  local child
  kill -STOP "$1" 2> /dev/null || return 0
  for child in $(pgrep -P "$1" || true); do kill_tree "$child"; done
  kill -KILL "$1" 2> /dev/null || true
}

# <pid> -> kills an orchestrator started by start_orchestrator, and reaps it so
# the shell does not print a job notice for the kill
stop_orchestrator() {
  kill_tree "$1"
  wait "$1" 2> /dev/null || true
}

body_of() { gh issue view "$1" --repo "$REPO" --json body --jq .body; }

# <issue-url> <session-uuid> -> claim-issue.sh's verdict on whether that
# session holds the latest claim: OWN, FOREIGN, UNCLAIMED or ERROR
claim_of() {
  local line
  line=$(CLAUDE_CODE_SESSION_ID="$2" "$SCRIPTS/claim-issue.sh" "$REPO" "${1##*/}" 2> /dev/null | tail -1) || true
  line=${line#result=}
  echo "${line%% *}"
}

# <run-dir> <run-id> -> files the parent and both children and links them,
# writing each URL to <run-dir>/{parent,a,b} as it is filed, so clean_up finds
# whatever exists when a later step fails
file_fixture() {
  local dir=$1 run=$2 fix="$HERE/fixtures" date parent a b
  date=$(date -u +%Y-%m-%d)
  echo "This is a **tracking issue**; its design is written once its children are filed." > "$dir/parent.md"
  parent=$(file_issue "$dir/parent" "[restart eval $run] Greeting files" "$dir/parent.md") || return 1
  render "$fix/child-a.md" PARENT="$parent" RUN="$run" > "$dir/a.md"
  a=$(file_issue "$dir/a" "[restart eval $run] Name file" "$dir/a.md") || return 1
  render "$fix/child-b.md" PARENT="$parent" RUN="$run" > "$dir/b.md"
  b=$(file_issue "$dir/b" "[restart eval $run] Greeting file" "$dir/b.md") || return 1
  render "$fix/parent.md" RUN="$run" DATE="$date" CHILD_A="$a" CHILD_B="$b" > "$dir/parent.md"
  gh issue edit "$parent" --repo "$REPO" --body-file "$dir/parent.md" > /dev/null || return 1
  gh issue edit "$parent" --repo "$REPO" --add-sub-issue "$a,$b" > /dev/null || return 1
}

# <url-file> <title> <body-file> -> files the issue, records its URL in
# <url-file>, and prints it
file_issue() {
  local url
  url=$(gh issue create --repo "$REPO" --title "$2" --body-file "$3" | tail -1) || return 1
  case "$url" in https://*/issues/[0-9]*) ;; *) return 1 ;; esac
  echo "$url" | tee "$1"
}

# <run-dir> <name> <session-uuid> <prompt> -> clones REPO to <run-dir>/<name>,
# starts an orchestrator there in the background, and sets ORCH_PID to its pid.
# Not called in a command substitution, so the orchestrator stays this shell's
# child.
start_orchestrator() {
  local dir=$1 name=$2
  ORCH_PID=""
  gh repo clone "$REPO" "$dir/$name" -- -q 2> /dev/null || return 1
  (
    cd "$dir/$name"
    exec env -u CLAUDE_CODE_SESSION_ID "$CLAUDE" -p --session-id "$3" \
      --output-format stream-json --verbose --setting-sources "" \
      --plugin-dir "$TREE/dnbg-workflow" --permission-mode bypassPermissions \
      ${MODEL:+--model "$MODEL"} ${MAX_BUDGET_USD:+--max-budget-usd "$MAX_BUDGET_USD"} \
      <<< "$4" > "$dir/$name.jsonl" 2> "$dir/$name.stderr"
  ) &
  ORCH_PID=$!
  echo "$ORCH_PID" > "$dir/$name.pid"
}

# <iso> <seconds> -> the UTC time that many seconds before <iso>, as an iso
iso_before() {
  local t
  t=$(TZ=UTC date -j -f %Y-%m-%dT%H:%M:%SZ "$1" +%s 2> /dev/null || date -u -d "$1" +%s)
  t=$(( t - $2 ))
  date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || date -u -d "@$t" +%Y-%m-%dT%H:%M:%SZ
}

# <deadline> -> 0 while it is still ahead
before() { [ "$(date +%s)" -lt "$1" ]; }

# <run-dir> <pid> <session-uuid> -> 0 once both children carry that session's
# claim; prints why not otherwise
await_claims() {
  local dir=$1 deadline=$(( $(date +%s) + ${CLAIM_TIMEOUT:-900} ))
  while before "$deadline"; do
    kill -0 "$2" 2> /dev/null || { echo "the first orchestrator exited before claiming both children"; return 1; }
    [ "$(claim_of "$(cat "$dir/a")" "$3")" = OWN ] && [ "$(claim_of "$(cat "$dir/b")" "$3")" = OWN ] && return 0
    sleep 15
  done
  echo "the first orchestrator did not claim both children in ${CLAIM_TIMEOUT:-900}s"
  return 1
}

# <run-dir> <pid> <since> <value> <comment-id> -> 0 once kill_due holds on the
# parent; prints why not otherwise.
#
# The watch wakes on a body edit and the parent closing, nothing else: the
# decision lands as a body edit under the operator's login, the one login every
# comment in the run also posts under.
await_kill_point() {
  local dir=$1 parent n since=$3 deadline=$(( $(date +%s) + ${KILL_TIMEOUT:-1800} )) wpid result
  parent=$(cat "$dir/parent"); n=${parent##*/}
  while before "$deadline"; do
    SETTLE=0 INTERVAL=3 WINDOW=$(( deadline - $(date +%s) )) \
      "$SCRIPTS/watch-issue.sh" "$REPO" "$n" --role=author --wake-on=body-edit,close \
      --since="$since" > "$dir/watch.out" 2> /dev/null &
    wpid=$!
    while kill -0 "$wpid" 2> /dev/null; do
      if ! kill -0 "$2" 2> /dev/null; then
        kill_tree "$wpid"
        echo "the first orchestrator exited before writing the decision"
        return 1
      fi
      sleep 1
    done
    wait "$wpid" || true
    result=$(grep '^result=' "$dir/watch.out" | tail -1)
    case "$result" in
      result=ACTIVITY*) ;;
      result=IDLE*) kill_due "$(body_of "$parent")" "$4" "$5" && return 0; break ;;
      result=CLOSED*) echo "the parent was closed before the decision reached it"; return 1 ;;
      *) echo "the parent's watch failed: ${result:-no result}"; return 1 ;;
    esac
    # The next watch looks back past this one's `now`, since an edit GitHub
    # stamps in the same second as `now`, or behind it by clock skew, would
    # otherwise never wake it. The body is read after `now`, so an edit seen
    # twice is only read twice.
    since=$(iso_before "${result##* now=}" 5)
    kill_due "$(body_of "$parent")" "$4" "$5" && return 0
  done
  echo "the decision did not reach the parent's design and log in ${KILL_TIMEOUT:-1800}s"
  return 1
}

# <run-dir> <pid> <session-uuid> <value> <comment-id> -> 0 once resume_missing
# is empty; prints what is still missing otherwise
await_resume() {
  local dir=$1 deadline=$(( $(date +%s) + ${RESUME_TIMEOUT:-2700} )) todo="" parent_body b_body
  while before "$deadline"; do
    if parent_body=$(body_of "$(cat "$dir/parent")") && b_body=$(body_of "$(cat "$dir/b")"); then
      todo=$(resume_missing "$parent_body" "$b_body" "$4" "$5" \
        "$(claim_of "$(cat "$dir/a")" "$3")" "$(claim_of "$(cat "$dir/b")" "$3")")
      [ -z "$todo" ] && return 0
    fi
    kill -0 "$2" 2> /dev/null || { echo "the fresh orchestrator exited with: $todo"; return 1; }
    sleep 20
  done
  echo "after ${RESUME_TIMEOUT:-2700}s: $todo"
  return 1
}

# <run-dir> -> closes the run's PRs, deleting their branches, then its issues
clean_up() {
  local dir=$1 f url pr
  for f in a b parent; do
    [ -s "$dir/$f" ] || continue
    url=$(cat "$dir/$f")
    for pr in $("$SCRIPTS/pr-sources.sh" "$REPO" "${url##*/}" 2> /dev/null | awk '/^https:/ { print $1 }'); do
      [ "$(gh pr view "$pr" --json state --jq .state 2> /dev/null)" = OPEN ] \
        && { gh pr close "$pr" --delete-branch --comment "Closed by the restart eval at the end of its run." > /dev/null 2>&1 || true; }
    done
    gh issue close "$url" --repo "$REPO" --reason "not planned" \
      --comment "Closed by the restart eval at the end of its run." > /dev/null 2>&1 || true
  done
}

# <run-dir> <run-id> -> PASS, FAIL or INCONCLUSIVE, with a reason
run_once() {
  local dir=$1 run=$2 first second pid value comment cid since why parent
  first=$(uuidgen | tr '[:upper:]' '[:lower:]')
  second=$(uuidgen | tr '[:upper:]' '[:lower:]')
  value="ahoy-$run"

  file_fixture "$dir" "$run" || { echo "FAIL the fixture could not be filed"; return; }
  parent=$(cat "$dir/parent")

  start_orchestrator "$dir" first "$first" "Orchestrate the resolution of $parent." \
    || { echo "FAIL $REPO could not be cloned"; return; }
  pid=$ORCH_PID
  if ! why=$(await_claims "$dir" "$pid" "$first"); then stop_orchestrator "$pid"; echo "FAIL $why"; return; fi

  since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  comment=$(gh issue comment "$parent" --repo "$REPO" --body "Decision: R2 changes to: \`restart-eval/$run/greeting.txt\` holds the single line \`$value\` instead of \`hello\`.") \
    || { stop_orchestrator "$pid"; echo "FAIL the decision comment could not be posted"; return; }
  cid=${comment##*issuecomment-}
  case "$cid" in ''|*[!0-9]*) stop_orchestrator "$pid"; echo "FAIL no comment id in '$comment'"; return ;; esac
  if ! why=$(await_kill_point "$dir" "$pid" "$since" "$value" "$cid"); then
    stop_orchestrator "$pid"; echo "FAIL $why"; return
  fi
  stop_orchestrator "$pid"

  local parent_body b_body
  if ! parent_body=$(body_of "$parent") || ! b_body=$(body_of "$(cat "$dir/b")"); then
    echo "FAIL the bodies could not be read after the kill"; return
  fi
  why=$(swept_before_kill "$parent_body" "$b_body" "$value" "$cid")
  if [ -n "$why" ]; then echo "INCONCLUSIVE sweep completed before kill: $why"; return; fi

  start_orchestrator "$dir" second "$second" \
    "Orchestrate the resolution of $parent. This is a restart: the previous orchestrator, session ${first:0:8}, was killed, and it and all its subagents are gone. That answers the question of whether its claims have been let go: take them over." \
    || { echo "FAIL $REPO could not be cloned"; return; }
  pid=$ORCH_PID
  if ! why=$(await_resume "$dir" "$pid" "$second" "$value" "$cid"); then stop_orchestrator "$pid"; echo "FAIL $why"; return; fi
  stop_orchestrator "$pid"
  echo PASS
}

main() {
  RUNS=${RUNS:-1}
  case "$RUNS" in
    ''|*[!0-9]*|0) echo "RUNS must be a positive integer, got '$RUNS'" >&2; exit 2 ;;
  esac
  CLAUDE=$(command -v "${CLAUDE_BIN:-claude}") || { echo "no claude binary: ${CLAUDE_BIN:-claude}" >&2; exit 2; }
  local out stamp i dir verdict passed=0 inconclusive=0
  gh api user --jq .login > /dev/null || { echo "gh is not logged in" >&2; exit 2; }
  out=${EVAL_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/restart-eval.XXXXXX")}
  stamp=$(date -u +%Y%m%d%H%M%S)

  for i in $(seq 1 "$RUNS"); do
    dir="$out/run-$i"
    rm -rf "$dir"; mkdir -p "$dir"
    # Through a file, not a command substitution, so the orchestrators stay
    # children of this shell; anything else run_once prints lands above the
    # verdict, which is its last line.
    # An interrupt stops the orchestrator in flight, which would otherwise keep
    # spending and writing to REPO, and still cleans up.
    trap 'stop_orchestrator "${ORCH_PID:-}"; [ "${KEEP:-}" = 1 ] || clean_up "$dir"; exit 130' INT TERM
    run_once "$dir" "$stamp-$i" > "$dir/verdict"
    trap - INT TERM
    verdict=$(tail -1 "$dir/verdict")
    echo "run $i: $verdict ($(cat "$dir/parent" 2> /dev/null || echo "no parent filed"))"
    case "$verdict" in
      PASS) passed=$((passed + 1)) ;;
      INCONCLUSIVE*) inconclusive=$((inconclusive + 1)) ;;
    esac
    [ "${KEEP:-}" = 1 ] || clean_up "$dir"
  done

  echo "passed $passed/$RUNS, inconclusive $inconclusive, failed $((RUNS - passed - inconclusive))"
  echo "artifacts: $out"
  [ "$passed" -eq "$RUNS" ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
