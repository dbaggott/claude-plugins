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

load hook-env

setup() { hook_env_setup; }

run_hook() { run_hook_at "$HOOK" "$@"; }
run_hook_configured() { run_hook_configured_at "$HOOK" "$@"; }

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

# --- version stamp -----------------------------------------------------------
#
# The stamp is what lets a published review or PR be attributed to the prompts
# that produced it. Nothing else carries the version — a transcript records the
# plugin's name and Claude Code's version, never this plugin's — so if the hook
# stops emitting it, the attribution is lost silently and only shows up as a gap
# in analysis months later.

@test "emits the plugin version when the manifest is readable" {
  stub_path jq git gh
  write_manifest 2026.8.32
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"## dnbg-workflow 2026.8.32"* ]]
}

@test "stays silent about the version when the manifest is missing" {
  # A broken install loses the stamp, not the rules.
  stub_path jq git gh
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Always do the thing."* ]]
  [[ "$output" != *"## dnbg-workflow "* ]]
}

@test "drops the version rather than the rules when jq is absent" {
  # `jq` reads the manifest, and its absence already disables the gates. Losing
  # the stamp too is the acceptable half; losing the rules with it is not.
  stub_path git gh
  write_manifest 2026.8.32
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Always do the thing."* ]]
  [[ "$output" != *"2026.8.32"* ]]
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

@test "the jq notice says subagents lose the rules, which nothing else reports" {
  # `inject-rules-subagent.sh` exits quietly without jq. That is only acceptable
  # because this notice exists — a hook emitting nothing is indistinguishable
  # from one with nothing to say, so this sentence is the operator's sole signal
  # that delegated work is running unbound.
  stub_path git gh
  run_hook
  [[ "$output" == *"Subagents spawned this session do not receive the rules"* ]]
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

@test "with jq missing too, the git message drops its still-gated claim" {
  # The degraded message says check-issue-create still gates a --repo-qualified
  # command. That holds only while jq is present: with no parser the hook aborts
  # at its first jq call, before it ever reaches the --repo extraction, so it
  # gates nothing. Printed anyway, it would contradict the INACTIVE block right
  # above it — injected context asserting a gate is live while it is inert,
  # which is the failure this whole preflight exists to remove.
  stub_path
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"enforcement is DEGRADED"* ]]
  [[ "$output" != *"does still gate"* ]]
}

@test "with only git missing, the still-gated claim is present" {
  # The other half: conditioning the sentence must not delete it outright, or
  # the degraded case understates what is still protected.
  stub_path jq gh
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"does still gate"* ]]
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

# --- configuration overrides -------------------------------------------------
#
# The note is the *only* channel telling a session that a mechanical default has
# moved. The skills state the defaults literally — which is what keeps an
# unconfigured session identical to one from before the knobs existed — so a note
# that fails to print is a session silently using the wrong directory or the
# wrong label.

@test "says nothing about configuration when neither knob is set" {
  # The default install must pay no tokens for a note with nothing to report.
  stub_path jq git gh
  run_hook
  [ "$status" -eq 0 ]
  [ "$output" = "$RULES_TEXT" ]
}

@test "says nothing when a knob is set to the value it already had" {
  # Configuring `.worktrees` is not an override, and announcing it as one would
  # be noise the reader has to work out is a no-op.
  stub_path jq git gh
  run_hook_configured '.worktrees' 'assigned:agent-session'
  [ "$status" -eq 0 ]
  [ "$output" = "$RULES_TEXT" ]
}

@test "announces a configured worktree root and names it" {
  stub_path jq git gh
  run_hook_configured 'wt' ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"configuration overrides"* ]]
  [[ "$output" == *'`wt/`'* ]]
}

@test "announces a configured claim label and names it" {
  stub_path jq git gh
  run_hook_configured '' 'assigned:my-bot'
  [ "$status" -eq 0 ]
  [[ "$output" == *"configuration overrides"* ]]
  [[ "$output" == *'`assigned:my-bot`'* ]]
}

@test "announces only the knob that moved" {
  # Both are reported from the same block, so a bug that prints both whenever
  # either is set would be invisible to the two tests above.
  stub_path jq git gh
  run_hook_configured 'wt' ''
  [[ "$output" == *'`wt/`'* ]]
  [[ "$output" != *"claim label is"* ]]
}

@test "the override note tells the reader it wins over the skills" {
  # Without this the agent has two sources — the skill's literal default and the
  # note — and no stated precedence between them.
  stub_path jq git gh
  run_hook_configured 'wt' ''
  [[ "$output" == *"win over the skills"* ]]
}

@test "a rejected worktree path is reported with its value, reason and fallback" {
  stub_path jq git gh
  run_hook_configured '/tmp/wt' ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"INVALID configuration"* ]]
  [[ "$output" == *'`/tmp/wt`'* ]]
  [[ "$output" == *"absolute path"* ]]
  [[ "$output" == *'`.worktrees`'* ]]
}

@test "a rejected claim label is reported with its value, reason and fallback" {
  stub_path jq git gh
  run_hook_configured '' 'in-progress'
  [ "$status" -eq 0 ]
  [[ "$output" == *"INVALID configuration"* ]]
  [[ "$output" == *'`in-progress`'* ]]
  [[ "$output" == *"outside the"* ]]
  [[ "$output" == *'`assigned:agent-session`'* ]]
}

@test "a rejected value produces no override note claiming it took effect" {
  # The failure mode this rules out: reporting the rejection and then announcing
  # an override anyway, which contradicts itself inside one message.
  stub_path jq git gh
  run_hook_configured '/tmp/wt' ''
  [[ "$output" == *"INVALID configuration"* ]]
  [[ "$output" != *"configuration overrides"* ]]
}

@test "the rejection is printed before any override it sits alongside" {
  # A reader who meets the override note first takes their configuration as
  # working, and the correction arrives after they have already believed it.
  stub_path jq git gh
  run_hook_configured '/tmp/wt' 'assigned:my-bot'
  [[ "$output" == *"INVALID configuration"*"configuration overrides"* ]]
}

@test "still emits the rules when a knob is configured" {
  # Same additive property the dependency preflight has: a configured session
  # must not trade its always-on rules for a note about a directory name.
  stub_path jq git gh
  run_hook_configured 'wt' 'assigned:my-bot'
  [[ "$output" == *"Always do the thing."* ]]
}

@test "exits 0 on a rejected configuration" {
  # A bad directory name is not worth failing a session start over, and a
  # non-zero exit here is itself a hook error notice.
  stub_path jq git gh
  run_hook_configured '../escape' 'nope'
  [ "$status" -eq 0 ]
}
