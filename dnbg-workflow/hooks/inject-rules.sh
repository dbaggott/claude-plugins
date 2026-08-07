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
exit 0
