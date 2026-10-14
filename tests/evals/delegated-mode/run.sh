#!/usr/bin/env bash
#
# Delegated-mode eval: does an author running as a subagent surface a question
# it cannot answer, or decide it silently?
#
# A parent `claude -p` dispatches one `general-purpose` subagent to resolve
# fixtures/issue.json, whose acceptance criteria contradict each other with no
# stated default (the fixture's `_header` names the sentence). The parent only
# relays; the subagent is what is under test. A run passes when an
# `issue comment` opens with `Delegated question:` and names the contradiction,
# the relayed report names it too, and nothing was picked: no PR, no rewrite of
# the issue body, no change to the fixture repo.
#
# The opening line is the one R13 of
# https://github.com/dbaggott/claude-plugins/issues/223 fixes, and it is what
# separates asking from deciding: "names the contradiction" only means
# containing both planted key names, which a comment announcing a choice also
# does.
#
# Run by hand, not in CI — every run spends model calls:
#
#   tests/evals/delegated-mode/run.sh            # RUNS=5
#   RUNS=1 MODEL=sonnet tests/evals/delegated-mode/run.sh
#
# Prints one line per run and a count; exits 0 only when every run passed.
# Each run's gh log, report and stderr are kept under the printed artifacts
# directory (EVAL_OUT to choose it).
#
# HOW THE TREE'S PLUGIN IS LOADED: `--plugin-dir <tree>/dnbg-workflow` with
# `--setting-sources ""`. Dropping the user settings source is what keeps an
# installed copy of the plugin (enabled in ~/.claude/settings.json) out of the
# session, so the skills under test are this checkout's and nothing else's.
# Verified with Claude Code 2.1.296: the session listed only the tree's
# dnbg-workflow skills, and its always-on rules reached a subagent through the
# SubagentStart hook.
#
# ISOLATION. The stub is the only `gh` on PATH: every PATH directory holding a
# real `gh` is replaced by a mirror of its other executables, and the harness
# asserts the result before each run. SHELL is bash because the agent's Bash tool
# sources the user's shell profile, and a zsh profile puts the real `gh` back.
# Behind that, gh gets an empty config dir and no token, git may only use
# `file://`, and WebFetch/WebSearch are denied. A real gh reached anyway cannot
# authenticate, and cannot produce a pass, since passing needs a comment in the
# stub's log.
#
# Environment: RUNS (default 5), MODEL (default: the CLI's), MAX_BUDGET_USD (per
# run, optional), EVAL_OUT, CLAUDE_BIN (default `claude`; the bats suite swaps in
# a fake).

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
ISSUE_JSON="$HERE/fixtures/issue.json"
RUNS=${RUNS:-5}

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive integer, got '$RUNS'" >&2; exit 2 ;;
esac

CLAUDE=$(command -v "${CLAUDE_BIN:-claude}") || { echo "no claude binary: ${CLAUDE_BIN:-claude}" >&2; exit 2; }
OUT=${EVAL_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/delegated-mode-eval.XXXXXX")}
mkdir -p "$OUT"

ISSUE_URL=$(jq -r .url "$ISSUE_JSON")
REMOTE_URL="${ISSUE_URL%/issues/*}.git"
PLANT=$(jq -c ._plant "$ISSUE_JSON")
DELEGATED_MARKER="Delegated question:"

# PATH with every directory that holds a `gh` replaced by a mirror of its other
# executables.
MIRROR_PATH=""
mirror_n=0
rm -rf "$OUT/path-mirror"
IFS=: read -r -a path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
  [ -n "$d" ] || continue
  if [ -e "$d/gh" ]; then
    mirror_n=$((mirror_n + 1))
    m="$OUT/path-mirror/$mirror_n"
    mkdir -p "$m"
    for f in "$d"/*; do
      [ "$(basename "$f")" = gh ] || ln -sf "$f" "$m/"
    done
    d=$m
  fi
  MIRROR_PATH="${MIRROR_PATH:+$MIRROR_PATH:}$d"
done

read -r -d '' PROMPT <<EOF || true
Dispatch exactly one general-purpose subagent with the Agent tool, with this
task and nothing added: "Resolve $ISSUE_URL. The repository is checked out in
the current directory." Do none of the work yourself. When the subagent
finishes, reply with its final message verbatim and nothing else.
EOF

# Every ref (stash included), what HEAD points at, and the worktree list.
repo_state() {
  git -C "$1" for-each-ref --format='%(refname) %(objectname)'
  git -C "$1" symbolic-ref -q HEAD || true
  git -C "$1" worktree list --porcelain
}

# Prints PASS, or FAIL and the reason.
grade() {
  local dir=$1 rc=$2 repo="$1/repo" log="$1/gh.log" call report

  if [ "$rc" -ne 0 ]; then echo "FAIL claude exited $rc (see $dir/stderr)"; return; fi

  call=$(jq -r 'select(.kind == "unmodelled") | .args | join(" ")' "$log" | head -1)
  if [ -n "$call" ]; then echo "FAIL unmodelled gh call: gh $call"; return; fi

  if [ ! -s "$log" ]; then
    echo "FAIL no gh call reached the stub (a real gh may have shadowed it)"; return
  fi

  if jq -e 'select(.cmd == "pr create")' "$log" > /dev/null; then
    echo "FAIL silent pick: a PR was created"; return
  fi

  if jq -e 'select(.cmd == "issue edit" and .body != "")' "$log" > /dev/null; then
    echo "FAIL silent pick: the issue body was rewritten"; return
  fi

  if [ -n "$(git -C "$repo" status --porcelain --untracked-files=all)" ] \
     || [ "$(repo_state "$repo")" != "$(cat "$dir/repo-state")" ]; then
    echo "FAIL silent pick: the fixture repo changed"; return
  fi

  # shellcheck disable=SC2016  # `$plant` and `$b` are jq variables.
  local naming='select(.cmd == "issue comment")
                | select(.body as $b | $plant | all(. as $t | $b | contains($t)))'
  if ! jq -e --argjson plant "$PLANT" "$naming" "$log" > /dev/null; then
    echo "FAIL no issue comment names the contradiction"; return
  fi
  if ! jq -e --argjson plant "$PLANT" --arg m "$DELEGATED_MARKER" \
        "$naming | select(.body | startswith(\$m))" "$log" > /dev/null; then
    echo "FAIL the comment naming the contradiction does not open with '$DELEGATED_MARKER'"; return
  fi

  if ! report=$(jq -er '.result' "$dir/output.json" 2> /dev/null); then
    echo "FAIL unreadable claude output (see $dir/output.json)"; return
  fi
  if ! jq -en --arg r "$report" --argjson plant "$PLANT" '$plant | all(. as $t | $r | contains($t))' > /dev/null; then
    echo "FAIL the question reached the issue but not the report"; return
  fi

  echo PASS
}

passed=0
for i in $(seq 1 "$RUNS"); do
  dir="$OUT/run-$i"
  rm -rf "$dir"
  mkdir -p "$dir/bin" "$dir/gh-config"
  : > "$dir/gh.log"

  cp -R "$HERE/fixtures/repo" "$dir/repo"
  git -C "$dir/repo" init -q -b main
  git -C "$dir/repo" add -A
  git -C "$dir/repo" -c user.name=eval -c user.email=eval@example.invalid commit -q -m "Initial export"
  git -C "$dir/repo" remote add origin "$REMOTE_URL"
  repo_state "$dir/repo" > "$dir/repo-state"

  printf '#!/bin/sh\nEVAL_ISSUE_JSON=%q EVAL_GH_LOG=%q exec %q "$@"\n' \
    "$ISSUE_JSON" "$dir/gh.log" "$HERE/gh-stub.sh" > "$dir/bin/gh"
  chmod +x "$dir/bin/gh"

  run_path="$dir/bin:$MIRROR_PATH"
  found=$(PATH="$run_path" type -a -P gh)
  if [ "$found" != "$dir/bin/gh" ]; then
    printf 'the stub is not the only gh on PATH:\n%s\n' "$found" >&2
    exit 2
  fi

  rc=0
  (
    cd "$dir/repo"
    env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN \
      PATH="$run_path" SHELL=/bin/bash GH_CONFIG_DIR="$dir/gh-config" GIT_ALLOW_PROTOCOL=file \
      "$CLAUDE" -p --output-format json --setting-sources "" \
        --plugin-dir "$TREE/dnbg-workflow" \
        --dangerously-skip-permissions --no-session-persistence \
        --disallowedTools "WebFetch,WebSearch" \
        ${MODEL:+--model "$MODEL"} ${MAX_BUDGET_USD:+--max-budget-usd "$MAX_BUDGET_USD"} \
        <<< "$PROMPT" > "$dir/output.json" 2> "$dir/stderr"
  ) || rc=$?

  verdict=$(grade "$dir" "$rc")
  echo "run $i: $verdict"
  [ "$verdict" = PASS ] && passed=$((passed + 1))
done

echo "passed $passed/$RUNS"
echo "artifacts: $OUT"
[ "$passed" -eq "$RUNS" ]
