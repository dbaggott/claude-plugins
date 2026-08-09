#!/usr/bin/env bats
#
# End-to-end tests for the two blocking hooks, driven through the same interface
# Claude Code uses: a JSON payload on stdin, and an exit code out. 0 allows, 2
# blocks.
#
# These run against real git repositories rather than mocks, because most of
# what the hooks decide — is this a worktree, is this file tracked — is answered
# by git itself. A mock would test the test.

# Required before `run` accepts an expected-status flag; the fail-open tests at
# the bottom of this file use `run -127`. CI pins bats 1.13.0, well past this.
bats_require_minimum_version 1.5.0

HOOKS="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks"

setup() {
  TMP="$(mktemp -d)"
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t
  git -C "$REPO" config user.name t
  echo tracked > "$REPO/tracked.txt"
  git -C "$REPO" add tracked.txt
  git -C "$REPO" commit -qm init
  set_origin 'git@github.com:acme-corp/repo.git'
  # A transcript that exists but has not loaded the skill — the state a real
  # session is in before `issue-workflow` is invoked. The hook fails *open* with
  # no transcript at all (see the test for that), so passing one is what puts
  # the block path under test.
  TRANSCRIPT="$TMP/transcript.jsonl"
  printf '{"role":"user","content":"hi"}\n' > "$TRANSCRIPT"
}

teardown() { rm -rf "$TMP"; }

set_origin() {
  git -C "$REPO" remote remove origin 2>/dev/null || true
  git -C "$REPO" remote add origin "$1"
}

# Edit/Write payloads name the file `file_path`; NotebookEdit uses
# `notebook_path`. Both are exercised below.
edit_payload() {
  printf '{"tool_name":"%s","tool_input":{"%s":"%s"}}' "${2:-Edit}" "${3:-file_path}" "$1"
}

run_worktree_hook() {  # <payload>
  run bash -c "printf '%s' '$1' | CLAUDE_PLUGIN_OPTION_OWNERS='${OWNERS-acme-corp}' '$HOOKS/check-worktree.sh'"
}

bash_payload() {  # <command> [transcript-override]
  jq -cn --arg c "$1" --arg cwd "$REPO" --arg t "${2-$TRANSCRIPT}" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd, transcript_path:$t}'
}

run_issue_hook() {  # <payload>
  run bash -c "printf '%s' '$1' | CLAUDE_PLUGIN_OPTION_OWNERS='${OWNERS-acme-corp}' '$HOOKS/check-issue-create.sh'"
}

# --- check-worktree ----------------------------------------------------------

@test "blocks a tracked file in the main checkout of a covered repo" {
  run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED by dnbg-workflow:check-worktree"* ]]
}

@test "allows the same file inside a worktree" {
  # The discriminator is that a worktree's .git is a file, not a directory.
  git -C "$REPO" worktree add -q "$TMP/wt" -b wt
  run_worktree_hook "$(edit_payload "$TMP/wt/tracked.txt")"
  [ "$status" -eq 0 ]
}

@test "allows an untracked file in the main checkout" {
  echo new > "$REPO/untracked.txt"
  run_worktree_hook "$(edit_payload "$REPO/untracked.txt")"
  [ "$status" -eq 0 ]
}

@test "allows a tracked file when the remote is a non-GitHub host" {
  # End-to-end form of the host bug: same owner name, different forge. Before
  # host scoping this was blocked, while every skill told the agent to run `gh`
  # against a remote where it cannot work.
  set_origin 'https://gitlab.com/acme-corp/repo.git'
  run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 0 ]
}

@test "still blocks the same owner on github.com" {
  # The other half of the pair — host scoping must not have disabled the gate.
  set_origin 'https://github.com/acme-corp/repo.git'
  run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 2 ]
}

@test "gh issue create is not gated for a non-GitHub remote" {
  set_origin 'https://gitlab.com/acme-corp/repo.git'
  run_issue_hook "$(bash_payload 'gh issue create --title x')"
  [ "$status" -eq 0 ]
}

@test "allows a tracked file when the owner is not covered" {
  set_origin 'git@github.com:someone-else/repo.git'
  run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 0 ]
}

@test "allows everything when owners is empty" {
  OWNERS='' run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 0 ]
}

@test "blocks a NotebookEdit, which names its target notebook_path" {
  cp "$REPO/tracked.txt" "$REPO/nb.ipynb"
  git -C "$REPO" add nb.ipynb && git -C "$REPO" commit -qm nb
  run_worktree_hook "$(edit_payload "$REPO/nb.ipynb" NotebookEdit notebook_path)"
  [ "$status" -eq 2 ]
}

@test "ignores tools it does not gate" {
  run_worktree_hook "$(edit_payload "$REPO/tracked.txt" Read)"
  [ "$status" -eq 0 ]
}

@test "allows a path outside any git repository" {
  echo x > "$TMP/loose.txt"
  run_worktree_hook "$(edit_payload "$TMP/loose.txt")"
  [ "$status" -eq 0 ]
}

# --- check-issue-create ------------------------------------------------------

@test "blocks gh issue create in a covered repo without the skill loaded" {
  run_issue_hook "$(bash_payload 'gh issue create --title x')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED by dnbg-workflow:check-issue-create"* ]]
}

@test "allows once the issue-workflow skill appears in the transcript" {
  printf '{"skill":"dnbg-workflow:issue-workflow"}\n' > "$TMP/t.jsonl"
  run_issue_hook "$(bash_payload 'gh issue create --title x' "$TMP/t.jsonl")"
  [ "$status" -eq 0 ]
}

@test "allows when there is no transcript to check — a deliberate fail-open" {
  # With no transcript the hook cannot know whether the skill loaded, and it
  # chooses to allow rather than block on an unanswerable question. Asserted so
  # the choice is visible: silently flipping it would make the gate fire in
  # contexts that have no transcript at all.
  run_issue_hook "$(bash_payload 'gh issue create --title x' '')"
  [ "$status" -eq 0 ]
}

@test "the block message alone does not satisfy the transcript check" {
  # The hook's own message names the skill in prose. If the check matched the
  # bare name, a retry after a block would be allowed through.
  printf 'Load the issue-workflow skill (Skill tool, name dnbg-workflow:issue-workflow)\n' > "$TMP/t.jsonl"
  run_issue_hook "$(bash_payload 'gh issue create --title x' "$TMP/t.jsonl")"
  [ "$status" -eq 2 ]
}

@test "honours a quoted --repo argument" {
  run_issue_hook "$(bash_payload 'gh issue create --repo "acme-corp/other" --title x')"
  [ "$status" -eq 2 ]
}

@test "an uncovered --repo overrides the covered cwd" {
  run_issue_hook "$(bash_payload 'gh issue create --repo someone-else/other --title x')"
  [ "$status" -eq 0 ]
}

@test "an earlier unrelated --repo does not decide the verdict" {
  # The segment scan starts at `gh issue create`; without it the first --repo,
  # belonging to a different command, would be read as this one's target.
  run_issue_hook "$(bash_payload 'gh pr list --repo someone-else/x && gh issue create --title y')"
  [ "$status" -eq 2 ]
}

@test "a line-continuation does not hide the command" {
  run_issue_hook "$(bash_payload 'gh issue \
create --title x')"
  [ "$status" -eq 2 ]
}

@test "ignores gh issue edit" {
  run_issue_hook "$(bash_payload 'gh issue edit 5 --add-label x')"
  [ "$status" -eq 0 ]
}

@test "ignores non-Bash tools" {
  run bash -c "printf '%s' '$(edit_payload "$REPO/tracked.txt")' | CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp '$HOOKS/check-issue-create.sh'"
  [ "$status" -eq 0 ]
}

# --- missing dependencies: the gates must fail open --------------------------
#
# Exit 2 is the *only* status that blocks; Claude Code classes any other
# non-zero as a non-blocking error and lets the tool call through. So what these
# assert is "not 2", not "0": the hook aborting under `set -e` with 127 — bash's
# command-not-found status, reached the moment the first `jq` runs — is a
# fail-open, and is the designed behavior. `run -127` states that expected
# status so bats does not warn about it on every run.
#
# Making the gates fail closed instead is not an option, and these tests are
# what stop someone "fixing" it that way. A gate learns which repo an edit
# targets by parsing its payload, so with no parser it cannot distinguish a
# covered repo from any other — the only reachable "closed" is blocking every
# Edit/Write on the machine, in projects the operator never listed. The
# session-start warning in inject-rules.sh covers the silence instead; see
# tests/inject-rules.bats.

# A PATH lacking jq but carrying what the hooks otherwise need. `command -v`
# cannot be shadowed into failing, so absence has to be built rather than faked.
path_without_jq() {
  STUB="$TMP/bin"
  mkdir -p "$STUB"
  local bin src
  for bin in bash cat dirname git sed tr grep head printf; do
    src="$(command -v "$bin")" || continue
    ln -sf "$src" "$STUB/$bin"
  done
}

@test "with jq missing, an edit in a covered repo is not blocked" {
  path_without_jq
  run -127 env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp \
    bash -c "printf '%s' '$(edit_payload "$REPO/tracked.txt")' | '$HOOKS/check-worktree.sh'"
  [ "$status" -ne 2 ]
}

@test "with jq missing, an edit in an unrelated repo is not blocked" {
  # The blast-radius half. A user who installed this at user scope must not find
  # every project on the machine uneditable because one binary is absent.
  path_without_jq
  echo loose > "$TMP/loose.txt"
  run -127 env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp \
    bash -c "printf '%s' '$(edit_payload "$TMP/loose.txt")' | '$HOOKS/check-worktree.sh'"
  [ "$status" -ne 2 ]
}

@test "with jq missing, gh issue create is not blocked" {
  path_without_jq
  run -127 env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp \
    bash -c "printf '%s' '$(bash_payload 'gh issue create --title x')' | '$HOOKS/check-issue-create.sh'"
  [ "$status" -ne 2 ]
}
