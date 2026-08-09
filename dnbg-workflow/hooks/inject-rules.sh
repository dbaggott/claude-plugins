#!/usr/bin/env bash
# SessionStart hook: emit the always-on rules into every session's context. The
# output is captured by Claude Code and prepended to the system prompt, so
# anything in always-on-rules.md behaves the same as text in CLAUDE.md — applied
# unconditionally to every response.
#
# Keep always-on-rules.md small: every byte here costs tokens on every session.
# Most guidance belongs in a skill (loaded on demand) instead.

set -u

# `${CLAUDE_PLUGIN_ROOT:-}` (not bare) keeps `set -u` from aborting if Claude
# Code ever invokes the hook without setting the var. The file-existence guard
# below then silently no-ops on the resulting `/always-on-rules.md` path,
# matching the broken-install behavior the comment promises.
RULES="${CLAUDE_PLUGIN_ROOT:-}/always-on-rules.md"

# Silent no-op if the file is missing (e.g. a broken install) — better to lose
# the rules than to block the session start.
[ -f "$RULES" ] && cat "$RULES"

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
