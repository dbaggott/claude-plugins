#!/usr/bin/env bash
# The session the README demo records. Everything on screen is real output —
# from dnbg-workflow/hooks/check-worktree.sh, from git, and from the GitHub API
# — so re-running this reproduces the recording rather than approximating it.
#
# Run it through `render.sh`, which records and renders; running it directly
# just replays the session in your terminal.
#
# The argument is a throwaway clone of a repo whose owner is in `owners`; this
# script creates a worktree inside it and removes it again on the next run.
set -euo pipefail

REPO="${1:?usage: demo.sh <path-to-throwaway-clone>}"
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/dnbg-workflow/hooks/check-worktree.sh"
BRANCH="fix-stale-token"

# The plugin config the hooks read. In a real session this comes from the
# operator's settings.json, set at plugin-enable time.
export CLAUDE_PLUGIN_OPTION_OWNERS=dbaggott

# Idempotent: the previous run left a worktree and a branch behind, and the
# recording has to start from the same state every time or the takes differ.
# Silent, because the recording starts here and setup noise would be its
# opening frame.
git -C "$REPO" worktree remove --force ".worktrees/$BRANCH" >/dev/null 2>&1 || true
git -C "$REPO" worktree prune >/dev/null 2>&1
git -C "$REPO" branch -D "$BRANCH" >/dev/null 2>&1 || true

dim()  { printf '\033[2m%s\033[0m\n' "$1"; }
say()  { printf '\033[1;36m%s\033[0m\n' "$1"; }
beat() { sleep "${1:-1.2}"; }

payload() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# No `clear` — the recording starts on a blank screen, and clearing only buys a
# leading frame with nothing on it. A still of this GIF has to say what is being
# demonstrated, since that is what a reduced-motion reader gets.
say "❯ claude"
dim  '  "fix the stale-token check in lib.sh"'
beat 1.8

printf '\n'
dim '  ● Edit  dnbg-workflow/hooks/lib.sh'
beat 1.0
printf '\n'

# Real hook, real payload, real exit code.
payload "$REPO/dnbg-workflow/hooks/lib.sh" | bash "$HOOK" || true
beat 4.0

printf '\n'
dim '  ● Bash  git worktree add ...'
beat 1.0
printf '\n'
git -C "$REPO" worktree add ".worktrees/$BRANCH" -b "$BRANCH" origin/main
beat 2.5

printf '\n'
dim "  ● Edit  .worktrees/$BRANCH/dnbg-workflow/hooks/lib.sh"
beat 1.0
payload "$REPO/.worktrees/$BRANCH/dnbg-workflow/hooks/lib.sh" | bash "$HOOK"
printf '\033[32m  ✓ allowed\033[0m\n'
beat 4.0

# Act two: the other end of the same workflow. Real reviews on a real PR,
# pulled live — `gh` has to be authenticated against a repo the bot has
# reviewed. Set DEMO_PR/DEMO_REPO to point it somewhere else.
clear
say "❯ gh pr view ${DEMO_PR:-94} --json reviews"
beat 1.2
printf '\n'
gh api "repos/${DEMO_REPO:-dbaggott/claude-plugins}/pulls/${DEMO_PR:-94}/reviews" --jq '
  [.[] | select(.state != "COMMENTED")][:2][]
    | "  \(.user.login)\n    \(.state)  at \(.submitted_at[11:16])\n    \(.body | split("\n")[0] | .[0:70])\n"'
beat 5.0
