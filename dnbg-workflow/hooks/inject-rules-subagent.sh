#!/usr/bin/env bash
# SubagentStart hook: emit the always-on rules into every subagent's context.
#
# `SessionStart` output reaches the main loop only — a subagent spawned from that
# session receives none of it. `docs/maintainers.md` records the measurement and
# the client version it was taken on. That gap is silent for exactly the rules that most
# need not to be: a subagent that has never been told to work in a worktree edits
# the main checkout, and one never told to reference issues by full URL writes
# `#19` into a PR body with nothing to catch it.
#
# The payload is shared with the SessionStart hook rather than restated here —
# see rules-payload.sh for why that is a file and not a coupling test.
#
# Two things differ from the SessionStart side, and nothing else does:
#
#   - **Encoding.** This event ignores bare stdout. It reads
#     `hookSpecificOutput.additionalContext`, so the payload is JSON-wrapped
#     below. (Verified both ways: bare stdout on this event reaches nothing.)
#   - **No dependency preflight.** That text is operator-facing and
#     session-scoped; a subagent can act on none of it and would pay its tokens
#     on every spawn.

set -u

PAYLOAD="$("$(dirname "$0")/rules-payload.sh")"

# A broken install (no rules file, nothing configured) produces an empty payload.
# Emitting `additionalContext: ""` would be a well-formed way of saying nothing;
# staying silent says the same thing and matches how the SessionStart side
# handles it.
[ -n "$PAYLOAD" ] || exit 0

# `jq` builds the envelope, the same as every other non-trivial JSON in this
# plugin. Hand-rolling the escaping to survive a jq-less machine was considered
# and rejected: `jq` is what both enforcement hooks and both watch scripts run
# on, so a machine without it has no gates and no watchers either — this hook
# going quiet is not what makes that install unusable, and a hand-rolled escaper
# is a correctness surface that buys nothing the operator can use.
#
# It is not silent, which was the objection worth answering: the SessionStart
# preflight already fires on a missing `jq`, and says there that subagents lose
# the rules too.
command -v jq >/dev/null 2>&1 || exit 0

printf '%s' "$PAYLOAD" | jq -Rs -c \
  '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: .}}'

exit 0
