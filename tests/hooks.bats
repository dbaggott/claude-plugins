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

# The payload reaches the hook on stdin via a file, never by interpolation into a
# quoted command string. The interpolated form held only while no test command
# contained a single quote; the first one that did would have broken in the
# harness, as a shell quoting error nowhere near the test that caused it.
#
# The owners value is `local` before it is exported, so it reaches this hook and
# no further. Exporting it unscoped would leave the first call's owners standing
# for a second call in the same test — no test does that today, which is exactly
# when the cheap version of this is worth taking.
run_hook() {  # <hook-script> <payload>
  local CLAUDE_PLUGIN_OPTION_OWNERS="${OWNERS-acme-corp}"
  local CLAUDE_PLUGIN_OPTION_WORKTREE_PATH="${WORKTREE_PATH-}"
  export CLAUDE_PLUGIN_OPTION_OWNERS CLAUDE_PLUGIN_OPTION_WORKTREE_PATH
  printf '%s' "$2" > "$TMP/payload.json"
  run "$HOOKS/$1" < "$TMP/payload.json"
}

run_worktree_hook() {  # <payload>
  run_hook check-worktree.sh "$1"
}

bash_payload() {  # <command> [transcript-override]
  jq -cn --arg c "$1" --arg cwd "$REPO" --arg t "${2-$TRANSCRIPT}" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd, transcript_path:$t}'
}

run_issue_hook() {  # <payload>
  run_hook check-issue-create.sh "$1"
}

# --- check-worktree ----------------------------------------------------------

@test "blocks a tracked file in the main checkout of a covered repo" {
  run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED by dnbg-workflow:check-worktree"* ]]
}

# The block message names the worktree root twice — in the `git worktree add`
# that creates it, and in the path the edit is told to retry against. Both are
# asserted, because an agent that is blocked acts on this text and nothing else.
# These two match the retry path by its root segment, since the repo root under
# `mktemp -d` differs per run; the symlink test below asserts it end-to-end.

@test "the block message names the default worktree root" {
  run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git worktree add .worktrees/<branch-name>"* ]]
  [[ "$output" == *"/.worktrees/<branch-name>/"* ]]
}

@test "the block message names a configured worktree root instead" {
  # A message naming a directory the rest of the session is told not to use is
  # worse than no message at all.
  WORKTREE_PATH=wt run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git worktree add wt/<branch-name>"* ]]
  [[ "$output" == *"/wt/<branch-name>/"* ]]
  [[ "$output" != *".worktrees"* ]]
}

@test "the block message falls back to the default on a rejected worktree root" {
  # The gate resolves through the same helper as the session-start note, so a
  # value that note rejected cannot reappear here as a runnable instruction.
  WORKTREE_PATH=/tmp/wt run_worktree_hook "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git worktree add .worktrees/<branch-name>"* ]]
  [[ "$output" != *"/tmp/wt"* ]]
}

# A symlinked route to the repo is the ordinary case, not a contrived one: on
# macOS `/tmp` is a link to `/private/tmp`, so any session working out of a temp
# checkout arrives this way, as do symlinked home and project directories.
@test "the block message stays repo-relative through a symlinked path" {
  # The repo root the message is built from is resolved; the payload's path is
  # not. Every command the blocked agent is handed is assembled from the file's
  # path, so an absolute one here sends it to a location that cannot exist.
  ln -s "$REPO" "$TMP/link"
  run_worktree_hook "$(edit_payload "$TMP/link/tracked.txt")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"File: tracked.txt"* ]]
  [[ "$output" == *"/.worktrees/<branch-name>/tracked.txt"* ]]
  # The two shapes a re-introduced prefix strip produces: the payload's spelling
  # surviving into the message, and a retry path that is two absolute paths
  # joined at a `//`.
  [[ "$output" != *"$TMP/link"* ]]
  [[ "$output" != *"//"* ]]
}

@test "allows an untracked file reached through a symlinked path" {
  ln -s "$REPO" "$TMP/link"
  echo new > "$REPO/untracked.txt"
  run_worktree_hook "$(edit_payload "$TMP/link/untracked.txt")"
  [ "$status" -eq 0 ]
}

# git C-quotes an awkward name by default, which is the same defect as the
# symlinked one — a name in the message that no command will accept. The three
# cases span the classes git quotes separately: `core.quotePath` governs the
# non-ASCII one alone, so a fix resting on it leaves the other two escaped.
@test "the block message names an awkwardly-named file unescaped" {
  local name
  # jq rather than `edit_payload`, whose printf cannot carry a quote or a tab
  # through a JSON string.
  for name in 'tracked-æ.txt' 'tracked-"q.txt' "$(printf 'tracked-\tt.txt')"; do
    echo tracked > "$REPO/$name"
    git -C "$REPO" add -- "$name"
    git -C "$REPO" commit -qm awkward
    run_worktree_hook "$(jq -cn --arg p "$REPO/$name" \
      '{tool_name:"Edit",tool_input:{file_path:$p}}')"
    [ "$status" -eq 2 ]
    [[ "$output" == *"File: $name"* ]]
    # The C-quoted forms of the three: \303 for the byte, \" for the quote, \t
    # for the tab. A backslash reaching the message at all is the defect.
    [[ "$output" != *'\'* ]]
  done
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

# --- the gate matches a COMMAND, not a mention of one -----------------------
#
# Every case below is a command that creates no issue. Each was blocked before
# https://github.com/dbaggott/claude-plugins/issues/59, and the payloads that trip
# it are the ones written while working on this repo.

@test "a quoted mention in a commit message is not an issue creation" {
  run_issue_hook "$(bash_payload 'git commit -m "document the gh issue create gate"')"
  [ "$status" -eq 0 ]
}

@test "a quoted mention in a review body is not an issue creation" {
  # The live failure: the reviewer bot blocked posting a review about this hook.
  run_issue_hook "$(bash_payload 'gh api repos/o/r/pulls/58/reviews -f body="I blocked your gh issue create call"')"
  [ "$status" -eq 0 ]
}

@test "a payload carrying a single quote reaches the hook intact" {
  # The harness guard for run_hook. Under the old interpolated form this payload
  # did not fail the assertion — it never reached the hook at all, dying as a
  # shell quoting error in the command the harness built.
  run_issue_hook "$(bash_payload "git commit -m \"don't document the gh issue create gate\"")"
  [ "$status" -eq 0 ]
}

@test "a mention inside a heredoc body is not an issue creation" {
  # ⚠️ THE CASE QUOTE-STRIPPING ALONE DOES NOT COVER, and the most common one here:
  # a heredoc body is not quoted, and heredocs are how commit messages and PR
  # bodies get written in this repo. Command-position matching is what catches it.
  run_issue_hook "$(bash_payload 'git commit -F - <<MSG
document the gh issue create gate
MSG')"
  [ "$status" -eq 0 ]
}

@test "a real invocation after a separator is still gated" {
  # The other half: narrowing the match must not open a hole. An invocation is a
  # command wherever it sits in the line.
  run_issue_hook "$(bash_payload 'git add -A && gh issue create --title x')"
  [ "$status" -eq 2 ]
}

@test "an env-prefixed invocation is still gated" {
  # ⚠️ THE FORM reviewer/references/issue-mode.md MANDATES for every `gh` call once a bot token is
  # exported. Anchoring the match straight to `gh` un-gates it — a hole worse than
  # the over-blocking the anchor was added to fix, because it fails OPEN on the
  # commonest real invocation in this repo.
  run_issue_hook "$(bash_payload 'env -u GH_TOKEN gh issue create --title x')"
  [ "$status" -eq 2 ]
}

@test "a var-assignment prefix is still gated" {
  run_issue_hook "$(bash_payload 'GH_TOKEN=abc gh issue create --title x')"
  [ "$status" -eq 2 ]
}

@test "a prefixed invocation after a separator is still gated" {
  run_issue_hook "$(bash_payload 'git add -A && env -u GH_TOKEN gh issue create --title x')"
  [ "$status" -eq 2 ]
}

@test "ignores gh issue edit" {
  run_issue_hook "$(bash_payload 'gh issue edit 5 --add-label x')"
  [ "$status" -eq 0 ]
}

@test "ignores non-Bash tools" {
  run_issue_hook "$(edit_payload "$REPO/tracked.txt")"
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

# These cannot use run_hook: stripping the environment is the whole point, so the
# hook has to be reached through `env -i`. The payload still travels as a value —
# an env var `env` hands over intact — rather than interpolated into a command.
run_hook_without_jq() {  # <hook-script> <payload>
  path_without_jq
  run -127 env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp \
    HOOK="$HOOKS/$1" PAYLOAD="$2" bash -c 'printf "%s" "$PAYLOAD" | "$HOOK"'
}

@test "with jq missing, an edit in a covered repo is not blocked" {
  run_hook_without_jq check-worktree.sh "$(edit_payload "$REPO/tracked.txt")"
  [ "$status" -ne 2 ]
}

@test "with jq missing, an edit in an unrelated repo is not blocked" {
  # The blast-radius half. A user who installed this at user scope must not find
  # every project on the machine uneditable because one binary is absent.
  echo loose > "$TMP/loose.txt"
  run_hook_without_jq check-worktree.sh "$(edit_payload "$TMP/loose.txt")"
  [ "$status" -ne 2 ]
}

@test "with jq missing, gh issue create is not blocked" {
  run_hook_without_jq check-issue-create.sh "$(bash_payload 'gh issue create --title x')"
  [ "$status" -ne 2 ]
}
