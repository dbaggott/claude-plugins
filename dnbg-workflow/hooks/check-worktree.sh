#!/usr/bin/env bash
# PreToolUse hook: block Edit/Write/NotebookEdit on tracked files in the main
# checkout of a covered repo, forcing the worktree + draft PR flow from the
# git-workflow skill.
#
# Exit 0 = allow. Exit 2 = block; stderr is shown to the agent.

set -e
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only intercept file-modifying tools. This set must stay in step with the
# matcher in hooks.json and with the tools named in always-on-rules.md — a tool
# missing from any of the three is editable in the main checkout without the
# gate firing.
case "$TOOL" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

# NotebookEdit names its target `notebook_path`, not `file_path`.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -z "$FILE_PATH" ] && exit 0

DIR=$(dirname "$FILE_PATH")
[ -d "$DIR" ] || exit 0

# Inside any git repo?
REPO_ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0

ORIGIN=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null) || exit 0
remote_is_covered "$ORIGIN" || exit 0

# Worktrees have `.git` as a regular file (containing `gitdir: ...`); the main
# checkout has `.git` as a directory. If it's a file, we're in a worktree — allow.
[ -f "$REPO_ROOT/.git" ] && exit 0

# Main checkout. Allow brand-new untracked files; block edits to tracked ones.
REL_PATH="${FILE_PATH#"$REPO_ROOT"/}"
git -C "$REPO_ROOT" ls-files --error-unmatch -- "$REL_PATH" >/dev/null 2>&1 || exit 0

# Resolved rather than hard-coded: an operator who moved the worktree root would
# otherwise be handed a `git worktree add` naming a directory the rest of the
# session is told not to use, and told to retry the edit at a path that will
# never exist. A block message is only worth printing if it is runnable.
WORKTREE_PATH=$(resolve_worktree_path)

cat >&2 <<EOF
BLOCKED by dnbg-workflow:check-worktree — Edit/Write on a tracked file in the
main checkout of a covered repo.

  Repo: $REPO_ROOT
  File: $REL_PATH

Per the git-workflow skill, code changes must go through a worktree + draft PR.
Create one (from inside the main checkout):

  git fetch origin
  git worktree add $WORKTREE_PATH/<branch-name> -b <branch-name> origin/<default-branch>

Then retry the edit against:

  $REPO_ROOT/$WORKTREE_PATH/<branch-name>/$REL_PATH
EOF
exit 2
