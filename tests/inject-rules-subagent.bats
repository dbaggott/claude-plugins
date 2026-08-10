#!/usr/bin/env bats
#
# Tests for the SubagentStart hook, which re-emits the always-on rules into each
# subagent because SessionStart output reaches the main loop and nothing else.
#
# Two properties carry the weight here, and neither is visible by reading the
# script:
#
#   - **The payload is the same one the session got.** A subagent working to a
#     different set of rules than its parent is the failure the whole change
#     exists to prevent, and it would be silent.
#   - **The JSON is well-formed.** This event reads
#     `hookSpecificOutput.additionalContext`; malformed JSON is not a partial
#     delivery, it is *no* delivery, and nothing on either side reports it. The
#     escaping is hand-rolled (see the script for why it must not need `jq`), so
#     it is pinned against hostile input rather than assumed.

bats_require_minimum_version 1.5.0

HOOK="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/inject-rules-subagent.sh"
PAYLOAD_SCRIPT="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/rules-payload.sh"

setup() {
  TMP="$(mktemp -d)"
  ROOT="$TMP/plugin"
  mkdir -p "$ROOT"
  RULES_TEXT='## Test rule
Always do the thing.'
  printf '%s\n' "$RULES_TEXT" > "$ROOT/always-on-rules.md"
}

teardown() { rm -rf "$TMP"; }

# As in inject-rules.bats: a PATH carrying only the named binaries, because
# `command -v` searches PATH and shadowing cannot make a binary absent. `awk` is
# in the always-included set here — it is what performs the JSON escaping, so a
# run without it is not testing this hook, it is testing a broken install.
stub_path() {  # <bin>...
  STUB="$TMP/bin"
  rm -rf "$STUB"; mkdir -p "$STUB"
  local bin src
  for bin in bash cat dirname awk "$@"; do
    src="$(command -v "$bin")" || { echo "test setup: $bin not on PATH" >&2; return 1; }
    ln -sf "$src" "$STUB/$bin"
  done
}

run_hook() {  # PATH comes from the preceding stub_path call
  run env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="${1-$ROOT}" "$HOOK"
}

run_hook_configured() {  # <worktree-path> <claim-label>
  run env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT" \
    CLAUDE_PLUGIN_OPTION_WORKTREE_PATH="$1" CLAUDE_PLUGIN_OPTION_CLAIM_LABEL="$2" "$HOOK"
}

# The injected text, decoded back out of the envelope. Every content assertion
# goes through this rather than grepping the raw JSON: a grep for `Test rule`
# passes just as happily on a payload no subagent can read, which is the one
# failure these tests exist to catch.
context_of() {  # <hook stdout>
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'
}

# --- the envelope ------------------------------------------------------------

@test "emits a single line of well-formed JSON" {
  stub_path
  run_hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
  printf '%s' "$output" | jq -e . >/dev/null
}

@test "names the event Claude Code dispatches it for" {
  stub_path
  run_hook
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "SubagentStart" ]
}

@test "carries the payload under additionalContext, the only field this event reads" {
  stub_path
  run_hook
  [ "$(context_of "$output")" = "$RULES_TEXT" ]
}

# --- the shared payload ------------------------------------------------------

@test "injects exactly what the session-start payload script emits" {
  stub_path
  run_hook
  local direct
  direct="$(env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT" "$PAYLOAD_SCRIPT")"
  [ "$(context_of "$output")" = "$direct" ]
}

@test "a configured worktree root reaches subagents, not just the main loop" {
  stub_path
  run_hook_configured "wt" "assigned:bot"
  local ctx; ctx="$(context_of "$output")"
  [[ "$ctx" == *"Worktrees live in \`wt/\`"* ]]
  [[ "$ctx" == *"The claim label is \`assigned:bot\`"* ]]
}

@test "a rejected configuration reaches subagents with its fallback" {
  stub_path
  run_hook_configured "/etc/outside" "assigned:bot"
  local ctx; ctx="$(context_of "$output")"
  [[ "$ctx" == *"INVALID configuration"* ]]
  # The fallback sentence wraps mid-phrase in the heredoc, so the assertion is on
  # the part that names the value — the substitution being tested — rather than
  # on prose whose line breaks are incidental.
  [[ "$ctx" == *"\`.worktrees\` instead"* ]]
}

# --- what it deliberately leaves out -----------------------------------------

@test "omits the dependency preflight, which a subagent cannot act on" {
  stub_path git gh   # jq absent: the preflight would shout about it
  run_hook
  [ "$status" -eq 0 ]
  local ctx; ctx="$(context_of "$output")"
  [[ "$ctx" != *"enforcement is INACTIVE"* ]]
  [[ "$ctx" == *"Test rule"* ]]
}

@test "escapes without jq, since a jq-less install is when the gates are already inert" {
  stub_path   # no jq on the hook's PATH at all
  run_hook
  [ "$status" -eq 0 ]
  # Decoded with the test's own jq, which the hook never had access to.
  [ "$(context_of "$output")" = "$RULES_TEXT" ]
}

# --- escaping ----------------------------------------------------------------

@test "round-trips quotes, backslashes and tabs" {
  printf '%s\n' 'He said "hi" and C:\path\to\thing' > "$ROOT/always-on-rules.md"
  printf '%s\n' 'a	tab and a trailing backslash \' >> "$ROOT/always-on-rules.md"
  stub_path
  run_hook
  [ "$status" -eq 0 ]
  diff <(context_of "$output") "$ROOT/always-on-rules.md"
}

@test "round-trips the real rules file" {
  stub_path
  run env -i PATH="$STUB" HOME="$TMP" \
    CLAUDE_PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../dnbg-workflow" "$HOOK"
  [ "$status" -eq 0 ]
  diff <(context_of "$output") "${BATS_TEST_DIRNAME}/../dnbg-workflow/always-on-rules.md"
}

@test "drops raw control characters rather than emitting invalid JSON" {
  printf 'before\001\014after\n' > "$ROOT/always-on-rules.md"
  stub_path
  run_hook
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e . >/dev/null    # would fail if emitted raw
  [ "$(context_of "$output")" = "beforeafter" ]
}

# --- broken installs ---------------------------------------------------------

@test "stays silent and exits 0 when the rules file is missing" {
  stub_path
  rm "$ROOT/always-on-rules.md"
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent when CLAUDE_PLUGIN_ROOT is unset rather than emitting an empty envelope" {
  stub_path
  run env -i PATH="$STUB" HOME="$TMP" "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
