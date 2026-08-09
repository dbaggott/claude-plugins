#!/usr/bin/env bats
#
# Tests for the SessionStart hook: rule injection, and the dependency preflight
# that tells both the operator and Claude when the enforcement gates are inert.
#
# The preflight exists because the gates fail *open*. A `PreToolUse` hook that
# aborts on a missing binary exits non-zero and non-2, which Claude Code treats
# as a non-blocking error — the edit proceeds, and Claude never sees the notice.
# So "is the warning emitted" is the only observable that distinguishes a
# protected session from an unprotected one, which is what these pin.

HOOK="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/inject-rules.sh"

setup() {
  TMP="$(mktemp -d)"
  ROOT="$TMP/plugin"
  mkdir -p "$ROOT"
  RULES_TEXT='## Test rule
Always do the thing.'
  printf '%s\n' "$RULES_TEXT" > "$ROOT/always-on-rules.md"
}

teardown() { rm -rf "$TMP"; }

# A PATH carrying only the named binaries. Shadowing is not an option: the hook
# asks `command -v`, which searches PATH for an executable, so the only way to
# make a binary absent is to build a PATH that genuinely lacks it.
#
# `bash` and `cat` are always included — the shebang's `env` resolves `bash`
# through PATH, and the hook emits its text with `cat`. A missing one of those
# would fail the test for a reason unrelated to what it is checking.
stub_path() {  # <bin>...
  STUB="$TMP/bin"
  rm -rf "$STUB"; mkdir -p "$STUB"
  local bin src
  for bin in bash cat "$@"; do
    src="$(command -v "$bin")" || { echo "test setup: $bin not on PATH" >&2; return 1; }
    ln -sf "$src" "$STUB/$bin"
  done
}

run_hook() {  # PATH comes from the preceding stub_path call
  run env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="${1-$ROOT}" "$HOOK"
}

# --- rule injection ----------------------------------------------------------

@test "emits the rules file" {
  stub_path jq git gh
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Always do the thing."* ]]
}

@test "exits 0 and stays silent when the rules file is missing" {
  # A broken install should not take the session down with it.
  stub_path jq git gh
  run_hook "$TMP/nonexistent"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- dependency preflight ----------------------------------------------------

@test "says nothing about dependencies when all of them are present" {
  # The output is injected into every session's context, so a preflight that
  # chatters on a healthy machine costs tokens on every session of every user.
  stub_path jq git gh
  run_hook
  [ "$status" -eq 0 ]
  [ "$output" = "$RULES_TEXT" ]
}

@test "names jq and states enforcement is inactive when jq is missing" {
  stub_path git gh
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *'enforcement is INACTIVE (`jq` is not installed)'* ]]
}

@test "names git and states enforcement is degraded when git is missing" {
  # Distinct from the jq case on purpose: without git, check-worktree cannot
  # fire at all but check-issue-create still gates a --repo-qualified command,
  # so reporting it as a flat "inactive" would overstate the damage.
  stub_path jq gh
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *'enforcement is DEGRADED (`git` is not installed)'* ]]
}

@test "reports a missing gh separately from the enforcement gates" {
  # gh affects what the skills can do, not what the hooks enforce. One message
  # covering both would misstate whichever half the reader acts on.
  stub_path jq git
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *'`gh` is not installed'* ]]
  [[ "$output" != *"enforcement is INACTIVE"* ]]
  [[ "$output" != *"enforcement is DEGRADED"* ]]
}

@test "reports every missing dependency, not just the first" {
  stub_path
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"enforcement is INACTIVE"* ]]
  [[ "$output" == *"enforcement is DEGRADED"* ]]
  [[ "$output" == *'`gh` is not installed'* ]]
}

@test "still emits the rules when a dependency is missing" {
  # The warning is additive. If it ever replaced the rules, a machine without jq
  # would lose the always-on guidance as well as the gates — the two failures
  # compounding in exactly the session least able to absorb them.
  stub_path
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Always do the thing."* ]]
}

@test "exits 0 with every dependency missing" {
  # A non-zero SessionStart exit is itself a hook error notice. The preflight
  # reports a broken environment; it must not become part of the breakage.
  stub_path
  run_hook
  [ "$status" -eq 0 ]
}
