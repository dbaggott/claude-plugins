#!/usr/bin/env bash
# PreToolUse hook: block Edit/Write on tracked files in the main checkout of a
# covered repo, forcing the worktree + draft PR flow from the git-workflow skill.
#
# Exit 0 = allow. Exit 2 = block; stderr is shown to the agent.

set -e
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only intercept file-modifying tools.
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

DIR=$(dirname "$FILE_PATH")
[ -d "$DIR" ] || exit 0

# Inside any git repo?
REPO_ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0

ORIGIN=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null) || exit 0
owner_is_covered "$(owner_from_remote "$ORIGIN")" || exit 0

# Worktrees have `.git` as a regular file (containing `gitdir: ...`); the main
# checkout has `.git` as a directory. If it's a file, we're in a worktree — allow.
[ -f "$REPO_ROOT/.git" ] && exit 0

# Main checkout. Allow brand-new untracked files; block edits to tracked ones.
REL_PATH="${FILE_PATH#"$REPO_ROOT"/}"
git -C "$REPO_ROOT" ls-files --error-unmatch -- "$REL_PATH" >/dev/null 2>&1 || exit 0

cat >&2 <<EOF
BLOCKED by dnbg-workflow:check-worktree — Edit/Write on a tracked file in the
main checkout of a covered repo.

  Repo: $REPO_ROOT
  File: $REL_PATH

Per the git-workflow skill, code changes must go through a worktree + draft PR.
Create one (from inside the main checkout):

  git fetch origin
  git worktree add .worktrees/<branch-name> -b <branch-name> origin/<default-branch>

Then retry the edit against:

  $REPO_ROOT/.worktrees/<branch-name>/$REL_PATH
EOF
exit 2
