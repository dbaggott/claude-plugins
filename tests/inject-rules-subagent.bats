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
#   - **The delivery is well-formed.** This event reads
#     `hookSpecificOutput.additionalContext`; malformed JSON is not a partial
#     delivery, it is *no* delivery, and nothing on either side reports it.

bats_require_minimum_version 1.5.0

HOOK="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/inject-rules-subagent.sh"
PAYLOAD_SCRIPT="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/rules-payload.sh"

load hook-env

setup() { hook_env_setup; }

run_hook() { run_hook_at "$HOOK" "$@"; }
run_hook_configured() { run_hook_configured_at "$HOOK" "$@"; }
run_hook_stamped() { run_hook_stamped_at "$HOOK" "$@"; }

# The injected text, decoded back out of the envelope. Every content assertion
# goes through this rather than grepping the raw JSON: a grep for `Test rule`
# passes just as happily on a payload no subagent can read, which is the one
# failure these tests exist to catch.
context_of() {  # <hook stdout>
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'
}

# --- the envelope ------------------------------------------------------------

@test "emits a single line of well-formed JSON" {
  stub_path jq
  run_hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
  printf '%s' "$output" | jq -e . >/dev/null
}

@test "names the event Claude Code dispatches it for" {
  stub_path jq
  run_hook
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "SubagentStart" ]
}

@test "carries the payload under additionalContext, the only field this event reads" {
  stub_path jq
  run_hook
  [ "$(context_of "$output")" = "$RULES_TEXT" ]
}

# --- the version stamp -------------------------------------------------------

@test "carries the version stamp through the envelope" {
  # A subagent publishes too — it opens PRs and posts reviews — so a stamp that
  # reached only the main loop would leave exactly the subagent-authored
  # artifacts unattributable. SessionStart output does not reach here at all,
  # which is why this needs its own assertion rather than trusting the coupling
  # test below: that test pins the two payloads equal, and would stay green with
  # the stamp missing from both.
  stub_path jq
  write_manifest 2026.8.32
  run_hook_stamped
  [ "$status" -eq 0 ]
  [[ "$(context_of "$output")" == *"## dnbg-workflow 2026.8.32"* ]]
}

@test "carries the opt-out through the envelope too" {
  # The option reaches a subagent's hook the same way it reaches the session's,
  # so a subagent must not stamp what its parent was told not to. Both halves are
  # env vars on the same process, and nothing else would notice them disagreeing.
  stub_path jq
  write_manifest 2026.8.32
  run_hook
  [ "$status" -eq 0 ]
  [[ "$(context_of "$output")" != *"2026.8.32"* ]]
}

# --- the shared payload ------------------------------------------------------

@test "injects exactly what the session-start payload script emits" {
  # Run with the stamp on and a manifest to read, so both sides have every
  # optional block in play. With neither, the two payloads agree on the rules
  # file alone and the comparison proves almost nothing.
  stub_path jq
  write_manifest 2026.8.32
  run_hook_stamped
  local direct
  direct="$(env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT" \
    CLAUDE_PLUGIN_OPTION_VERSION_STAMP=true "$PAYLOAD_SCRIPT")"
  [ "$(context_of "$output")" = "$direct" ]
}

@test "a configured worktree root reaches subagents, not just the main loop" {
  stub_path jq
  run_hook_configured "wt" "assigned:bot"
  local ctx; ctx="$(context_of "$output")"
  [[ "$ctx" == *"Worktrees live in \`wt/\`"* ]]
  [[ "$ctx" == *"The claim label is \`assigned:bot\`"* ]]
}

@test "a rejected configuration reaches subagents with its fallback" {
  stub_path jq
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
  stub_path jq   # git and gh absent: the preflight would report both
  run_hook
  [ "$status" -eq 0 ]
  local ctx; ctx="$(context_of "$output")"
  [[ "$ctx" != *"enforcement is DEGRADED"* ]]
  [[ "$ctx" != *"gh\` is not installed"* ]]
  [[ "$ctx" == *"Test rule"* ]]
}

# --- escaping ----------------------------------------------------------------
#
# The envelope is built by `jq`, so these pin the wiring rather than an escaper
# of our own: that the payload is handed to it raw, and comes back out byte for
# byte. Content that would break a naive `printf` assembly is what makes that
# observable.

@test "round-trips quotes, backslashes and tabs" {
  printf '%s\n' 'He said "hi" and C:\path\to\thing' > "$ROOT/always-on-rules.md"
  printf '%s\n' 'a	tab and a trailing backslash \' >> "$ROOT/always-on-rules.md"
  stub_path jq
  run_hook
  [ "$status" -eq 0 ]
  diff <(context_of "$output") "$ROOT/always-on-rules.md"
}

@test "round-trips the real rules file" {
  # Pointed at the real plugin, so the bytes under test are the ones a real
  # session gets rather than this suite's two-line fixture. Nothing is configured
  # and the stamp is off, which is a default install — so the payload is the
  # rules file and nothing else, and the comparison can be exact.
  local rules="${BATS_TEST_DIRNAME}/../dnbg-workflow/always-on-rules.md"
  stub_path jq
  run_hook "${BATS_TEST_DIRNAME}/../dnbg-workflow"
  [ "$status" -eq 0 ]
  diff <(context_of "$output") "$rules"
}

@test "escapes control characters rather than emitting them raw" {
  printf 'before\001after\n' > "$ROOT/always-on-rules.md"
  stub_path jq
  run_hook
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e . >/dev/null    # raw would be invalid JSON
  [ "$(context_of "$output")" = "$(printf 'before\001after')" ]
}

# --- degraded and broken installs --------------------------------------------

@test "stays silent without jq, the state the session-start preflight announces" {
  # Not a silent loss: inject-rules.sh's INACTIVE block says subagents lose the
  # rules, and `tests/inject-rules.bats` pins that it says so. A machine without
  # jq has no gates and no watchers either, so there is nothing for a
  # hand-rolled escaper here to preserve.
  stub_path   # no jq
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent and exits 0 when the rules file is missing" {
  stub_path jq
  rm "$ROOT/always-on-rules.md"
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent when CLAUDE_PLUGIN_ROOT is unset rather than emitting an empty envelope" {
  stub_path jq
  run env -i PATH="$STUB" HOME="$TMP" "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
