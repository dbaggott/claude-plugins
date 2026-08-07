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
echo "$CMD" | grep -qE '\bgh +issue +create\b' || exit 0

# Target comes from --repo/-R if present, else the calling directory's origin.
REPO_FLAG=$(echo "$CMD" | grep -oE '(--repo|-R)[= ]+[^ ]+' | head -1 | sed -E 's/^(--repo|-R)[= ]+//')
if [ -n "$REPO_FLAG" ]; then
  owner_is_covered "$(owner_from_repo_spec "$REPO_FLAG")" || exit 0
else
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  [ -n "$CWD" ] || exit 0
  ORIGIN=$(git -C "$CWD" remote get-url origin 2>/dev/null) || exit 0
  owner_is_covered "$(owner_from_remote "$ORIGIN")" || exit 0
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
