#!/usr/bin/env bash
# SessionStart hook: emit the always-on rules into every session's context. The
# output is captured by Claude Code and prepended to the system prompt, so
# anything in always-on-rules.md behaves the same as text in CLAUDE.md — applied
# unconditionally to every response.
#
# Keep always-on-rules.md small: every byte here costs tokens on every session.
# Most guidance belongs in a skill (loaded on demand) instead.

set -u
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

# `${CLAUDE_PLUGIN_ROOT:-}` (not bare) keeps `set -u` from aborting if Claude
# Code ever invokes the hook without setting the var. The file-existence guard
# below then silently no-ops on the resulting `/always-on-rules.md` path,
# matching the broken-install behavior the comment promises.
RULES="${CLAUDE_PLUGIN_ROOT:-}/always-on-rules.md"

# Silent no-op if the file is missing (e.g. a broken install) — better to lose
# the rules than to block the session start.
[ -f "$RULES" ] && cat "$RULES"

# --- configuration overrides -------------------------------------------------
#
# The skills state the mechanical defaults literally — `.worktrees/`,
# `assigned:agent-session` — which is what makes an unconfigured session
# byte-identical to one from before these knobs existed, and costs it nothing.
# When a knob *is* set, this note is the only thing that says so, and it says it
# where both audiences see it: the skills cannot carry the configured value
# themselves, because `${user_config.*}` substitutes nothing whatsoever when an
# option is unset (see lib.sh) and would leave an unconfigured reader staring at
# a literal placeholder where a path should be.
#
# Emitted only when something is actually configured, so the default install pays
# no tokens for a note with nothing to report — the same bar the dependency
# preflight below is held to.
#
# stdout, for the preflight's reasons: it reaches the operator *and* Claude, and
# an override only one of them can see is an override that half-happens.

CONFIGURED_WORKTREE_PATH="${CLAUDE_PLUGIN_OPTION_WORKTREE_PATH:-}"
CONFIGURED_CLAIM_LABEL="${CLAUDE_PLUGIN_OPTION_CLAIM_LABEL:-}"

WORKTREE_PATH_BAD=""
CLAIM_LABEL_BAD=""
[ -n "$CONFIGURED_WORKTREE_PATH" ] &&
  WORKTREE_PATH_BAD=$(worktree_path_rejection "$CONFIGURED_WORKTREE_PATH")
[ -n "$CONFIGURED_CLAIM_LABEL" ] &&
  CLAIM_LABEL_BAD=$(claim_label_rejection "$CONFIGURED_CLAIM_LABEL")

# Rejections first. A reader who sees only the override note below would take the
# default it names as their configuration working, when in fact their value was
# thrown away — so the reason has to arrive before, not after.
if [ -n "$WORKTREE_PATH_BAD" ] || [ -n "$CLAIM_LABEL_BAD" ]; then
  printf '\n## dnbg-workflow: INVALID configuration (ignored)\n\n'
fi

[ -n "$WORKTREE_PATH_BAD" ] && cat <<EOF
The configured worktree path \`$CONFIGURED_WORKTREE_PATH\` cannot be used:
$WORKTREE_PATH_BAD. Worktrees have to stay inside the repo, where \`.gitignore\`
covers them and \`git-workflow\`'s cleanup steps resolve. **Using
\`$DEFAULT_WORKTREE_PATH\` instead** — set a repo-relative path from \`/plugin\`
to change it.
EOF

[ -n "$CLAIM_LABEL_BAD" ] && cat <<EOF
The configured claim label \`$CONFIGURED_CLAIM_LABEL\` cannot be used:
$CLAIM_LABEL_BAD. \`issue-workflow\`'s in-progress check matches the
\`$CLAIM_LABEL_NAMESPACE\` prefix rather than an enumerated list, so a label
outside it makes this plugin's claims invisible to every other claimant and
theirs invisible here — two workers on one issue, which is what the label exists
to prevent. **Using \`$DEFAULT_CLAIM_LABEL\` instead.**
EOF

WORKTREE_PATH=$(resolve_worktree_path)
CLAIM_LABEL=$(resolve_claim_label)

# Compared against the defaults rather than against "was anything set", so an
# operator who configures a knob to the value it already had gets no note. There
# is nothing to override in that case, and a note claiming otherwise would be
# noise the reader has to work out is a no-op.
if [ "$WORKTREE_PATH" != "$DEFAULT_WORKTREE_PATH" ] || [ "$CLAIM_LABEL" != "$DEFAULT_CLAIM_LABEL" ]; then
  printf '\n## dnbg-workflow: configuration overrides\n\n'
  printf 'These win over the skills. Where a skill spells out a default below and this note names something else, use what this note says.\n\n'
fi

[ "$WORKTREE_PATH" != "$DEFAULT_WORKTREE_PATH" ] && cat <<EOF
- **Worktrees live in \`$WORKTREE_PATH/\`**, not the \`$DEFAULT_WORKTREE_PATH/\`
  that \`git-workflow\` and \`reviewer\` spell out. Create them at
  \`$WORKTREE_PATH/<branch-name>\`, remove them from there, and ensure
  \`$WORKTREE_PATH\` is in \`.gitignore\`.
EOF

[ "$CLAIM_LABEL" != "$DEFAULT_CLAIM_LABEL" ] && cat <<EOF
- **The claim label is \`$CLAIM_LABEL\`**, not the \`$DEFAULT_CLAIM_LABEL\` that
  \`issue-workflow\` spells out. Use it in that skill's \`gh label create\` and
  \`gh issue edit\` calls. The check for an *existing* claim is unchanged: it
  matches the whole \`$CLAIM_LABEL_NAMESPACE\` prefix, so it still sees claims
  made under any other name in that namespace.
EOF

# --- dependency preflight ----------------------------------------------------
#
# The blocking hooks need binaries this session may not have, and when one is
# absent they do not block — they fail *open*, leaving the gates inert while
# every skill still tells the agent they are live.
#
# `SessionStart` is the one event where a single message reaches both audiences:
# its stdout "is added as context that Claude can see and act on" and shows in
# the transcript, whereas a `PreToolUse` hook aborting on a missing binary exits
# non-zero and non-2, which the docs class as a non-blocking error — the action
# proceeds, the human gets a `hook error` notice naming the missing binary, and
# Claude never sees it at all. Hence stdout here, not stderr: stderr from a hook
# that exits 0 goes to the debug log only and is seen by nobody.
#
# Deliberately *not* fixed by making the gates fail closed. A gate learns which
# repo an edit targets by parsing its payload, so with no parser it cannot tell
# a covered repo from any other — "fail closed" could then only mean blocking
# every edit on the machine, in projects the operator never listed. See the
# README's Requirements section.

# Reported per binary rather than as one list: what each absence disables
# differs, and a message that conflates them is not actionable.
for bin in jq git; do
  command -v "$bin" >/dev/null 2>&1 && continue
  case "$bin" in
    jq)
      cat <<'EOF'

## dnbg-workflow: enforcement is INACTIVE (`jq` is not installed)

Both blocking hooks parse their stdin payload with `jq`, so neither can run.
Edits to tracked files in the main checkout of a covered repo are **not** being
blocked, and `gh issue create` is **not** being gated. Treat the worktree and
issue flows as advisory this session and follow them from the skills directly.
Install `jq` to restore enforcement.
EOF
      ;;
    git)
      cat <<'EOF'

## dnbg-workflow: enforcement is DEGRADED (`git` is not installed)

`check-worktree.sh` resolves the edited path to a repository with `git`, so
without it that gate never fires: edits to tracked files in the main checkout of
a covered repo are **not** being blocked.
EOF
      # Only true while `jq` is present, so it is only printed then. Without a
      # parser, `check-issue-create.sh` aborts at its first `jq` call — before
      # it ever reaches the `--repo` extraction — and gates nothing at all.
      # Printed unconditionally, this sentence would contradict the INACTIVE
      # block above it whenever both binaries are absent: injected context
      # telling the agent a gate is live while it is inert, which is the exact
      # failure this preflight exists to remove.
      command -v jq >/dev/null 2>&1 && cat <<'EOF'
`check-issue-create.sh` does still gate a `gh issue create` that names its
target with `--repo`, but cannot judge one that relies on the working directory.
EOF
      cat <<'EOF'
Install `git` to restore enforcement.
EOF
      ;;
  esac
done

# Separate from the block above: `gh` affects what the skills can do, not what
# the hooks enforce, so conflating the two would misstate both.
command -v gh >/dev/null 2>&1 || cat <<'EOF'

## dnbg-workflow: `gh` is not installed

Every workflow skill drives the GitHub CLI for its PR, issue, and review
operations, so they cannot run without it. Install it from https://cli.github.com
and authenticate with `gh auth login`.
EOF

exit 0
