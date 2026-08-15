#!/usr/bin/env bash
# PreToolUse hook: block `gh issue create` against a covered repo unless the
# issue-workflow skill has been loaded this session, forcing the
# self-documenting-issue flow from that skill.
#
# `gh issue edit` is deliberately unhooked: most edits are small (labels,
# status marks, typo fixes), and blocking them would tax exactly the cheap
# body maintenance the skill's "Maintaining issues" section asks for. Major
# rewrites carry creation-level stakes, but the command line can't tell the
# two apart.
#
# Exit 0 = allow. Exit 2 = block; stderr is shown to the agent.

set -e
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ "$TOOL" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Join shell line-continuations before matching anything below. Every match here
# is line-based, so a backslash-newline truncates the command and each half
# fails open: a `gh issue create` split across the break goes undetected, and a
# `--repo` written on the next line is invisible to the segment search, handing
# the verdict to the calling directory instead. A bare newline is deliberately
# left alone — that one genuinely separates commands.
CMD=${CMD//\\$'\n'/ }

# The phrase has to be a command, not a mention of one. Matching it anywhere in
# the string is content-blind: it fires on any command whose *payload* discusses
# issue creation, and the payloads most likely to do that are the ones written
# while working on this repo — review bodies, commit messages, issue text.
#
# Two independent narrowings, because neither covers the other:
#
#   MASK QUOTED SPANS — text inside "…" or '…' is an argument, so a mention there
#   is data. Handles `-m "document the gh issue create gate"`.
#
#   REQUIRE COMMAND POSITION — start of a line, or after a separator. This is the
#   half that matters most here, because A HEREDOC BODY IS NOT QUOTED and masking
#   alone leaves it matching. Heredocs are how commit messages and PR bodies are
#   written in this repo, so that is the common case, not the exotic one. Prose
#   names the command mid-sentence; an invocation starts one.
#
# Residual, and deliberately accepted: a heredoc line that *begins* with the
# phrase still matches. The asymmetry is what settles it — a false negative means
# a skill went unloaded, which `issue-workflow`'s own claim check largely covers,
# while a false positive blocks real work and points the author at a skill that
# has nothing to do with what they were doing. Precision over recall.
# ⚠️ COMMAND POSITION MEANS "AFTER ANY PREFIX RUN", NOT "IMMEDIATELY AFTER THE
# SEPARATOR". An invocation is routinely prefixed — `env -u GH_TOKEN gh issue
# create` is MANDATED by reviewer/references/issue-mode.md for every `gh` call once a bot token is
# exported, and `VAR=x gh …` is ordinary shell. Anchoring straight to `gh` un-gates
# all of those: the gate would fail open on the single commonest real invocation in
# this repo.
PREFIX='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|command|time|sudo|env([[:space:]]+(-[^[:space:]]+|[A-Z_][A-Z0-9_]*))*)[[:space:]]+)*'
SCAN=$(printf '%s' "$CMD" | sed -E 's/"[^"]*"/ /g; s/'"'"'[^'"'"']*'"'"'/ /g')
printf '%s\n' "$SCAN" | grep -qE "(^|[;&|(])[[:space:]]*${PREFIX}gh +issue +create\b" || exit 0

# Target comes from --repo/-R if present, else the calling directory's origin.
#
# Search only from the `gh issue create` onward. Scanning the whole command
# string lets an unrelated earlier flag decide the verdict — in
# `gh pr list --repo other/x && gh issue create --title y` the first --repo
# belongs to a different command entirely. The fallback below is belt-and-braces
# only: the grep above already proved the phrase is present, so an empty segment
# should be unreachable.
SEGMENT=$(printf '%s' "$CMD" | grep -oE '\bgh +issue +create\b.*' | head -1)
[ -n "$SEGMENT" ] || SEGMENT="$CMD"

# `tr -d` strips quotes: the `[^ ]+` above captures them, and `--repo "own/rep"`
# is an entirely ordinary way to write the flag. Left in, the quote characters
# make the owner comparison fail and the hook allows what it should block.
# GitHub logins and repo names contain no quotes, so removing them cannot
# corrupt a legitimate value.
REPO_FLAG=$(printf '%s' "$SEGMENT" | grep -oE '(--repo|-R)[= ]+[^ ]+' | head -1 \
  | sed -E 's/^(--repo|-R)[= ]+//' | tr -d "\"'")
if [ -n "$REPO_FLAG" ]; then
  owner_is_covered "$(owner_from_repo_spec "$REPO_FLAG")" || exit 0
else
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  [ -n "$CWD" ] || exit 0
  ORIGIN=$(git -C "$CWD" remote get-url origin 2>/dev/null) || exit 0
  remote_is_covered "$ORIGIN" || exit 0
fi

# Was the skill loaded this session? A Skill tool invocation lands in the
# transcript as compact JSON: {"skill":"dnbg-workflow:issue-workflow",...}.
# Matching that structure (not the bare skill name) keeps this hook's own
# block message — which names the skill in prose — from satisfying the check
# on a retry.
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
grep -qE '"skill" *: *"(dnbg-workflow:)?issue-workflow"' "$TRANSCRIPT" && exit 0

cat >&2 <<'EOF'
BLOCKED by dnbg-workflow:check-issue-create — `gh issue create` against a
covered repo without the issue-workflow skill loaded.

Issues are handoffs: the resolver reads the body cold, so the body must carry
the proposed approach, acceptance criteria, and labeled cross-references.

Load the issue-workflow skill (Skill tool, name dnbg-workflow:issue-workflow),
shape the issue body per its "Creating issues" section, then retry.
EOF
exit 2
