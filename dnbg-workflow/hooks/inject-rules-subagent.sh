#!/usr/bin/env bash
# SubagentStart hook: emit the always-on rules into every subagent's context.
#
# `SessionStart` output reaches the main loop only — a subagent spawned from that
# session receives none of it. Measured on Claude Code 2.1.226, for the
# `general-purpose` and `Explore` agent types; the README records it. That gap is
# silent for exactly the rules that most need not to be: a subagent that has
# never been told to work in a worktree edits the main checkout, and one never
# told to reference issues by full URL writes `#19` into a PR body with nothing
# to catch it.
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

# Escape stdin as the body of a JSON string — no surrounding quotes, no trailing
# newline. Deliberately not `jq -Rs`: the preflight in inject-rules.sh exists
# because `jq` may be absent, and injecting the rules is the one thing this
# plugin still does correctly in that state. Requiring a parser here would make
# a jq-less install lose the subagent rules too — silently, since a hook that
# emits nothing looks exactly like one with nothing to say.
#
# Covers the escapes JSON requires for text this file can actually carry, and
# drops the remaining C0 control characters rather than emitting them raw, where
# they would be invalid JSON and cost the subagent the whole payload. Markdown
# authored in this repo contains none; the strip is what keeps that a fact about
# the output rather than an assumption about the input.
json_escape() {
  awk '
    BEGIN { ORS = ""; sep = "" }
    {
      s = $0
      gsub(/\\/, "\\\\", s)
      gsub(/"/,  "\\\"", s)
      gsub(/\t/, "\\t",  s)
      gsub(/\r/, "\\r",  s)
      gsub(/[\001-\010\013\014\016-\037\177]/, "", s)
      print sep s
      sep = "\\n"
    }
  '
}

PAYLOAD="$("$(dirname "$0")/rules-payload.sh")"

# A broken install (no rules file, nothing configured) produces an empty payload.
# Emitting `additionalContext: ""` would be a well-formed way of saying nothing;
# staying silent says the same thing and matches how the SessionStart side
# handles it.
[ -n "$PAYLOAD" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}\n' \
  "$(printf '%s\n' "$PAYLOAD" | json_escape)"

exit 0
