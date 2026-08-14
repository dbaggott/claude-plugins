#!/usr/bin/env bash
# The session the README demo records. The hook output, the git output and the
# review formatting are all produced live — nothing on screen is retyped.
#
# It is also reproducible, which is what lets check-render.sh verify the
# committed .cast against a fresh run. Two things buy that: the repo it drives
# is built here rather than passed in, from pinned content and pinned commit
# dates, so its path and its commit SHA are the same on every machine; and the
# reviews come from a committed fixture rather than the live API, whose bodies
# and timestamps nothing can hold still.
#
# Run it through render.sh, which records and renders every demo; running it
# directly just replays this one in your terminal.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../../dnbg-workflow/hooks/check-worktree.sh"
BRANCH="fix-stale-token"

# An absolute path rather than a temp dir, because it is on screen: the block
# message names the repo root, and a $TMPDIR path would differ per machine and
# per OS in both length and content — which changes where the message wraps.
DEMO_ROOT="/tmp/dnbg-demo"
REPO="$DEMO_ROOT/claude-plugins"

# The plugin config the hooks read. In a real session this comes from the
# operator's settings.json, set at plugin-enable time.
export CLAUDE_PLUGIN_OPTION_OWNERS=dbaggott

# Pinned at the source so a recording and a check-render.sh run produce the same
# bytes on any machine: `clear` emits whatever TERM describes, and git's output
# answers to the operator's global config.
export TERM=xterm-256color
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# Built from scratch each run, so the recording starts from the same state every
# time. Pinned identity and dates make the commit SHA deterministic — it is on
# screen in the `worktree add` output. Silent, because the recording starts here
# and setup noise would be its opening frame.
build_repo() {
  rm -rf "$DEMO_ROOT"
  mkdir -p "$REPO/dnbg-workflow/hooks"
  printf 'x\n' > "$REPO/dnbg-workflow/hooks/lib.sh"
  git -C "$REPO" init -q -b main
  git -C "$REPO" add -A
  GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' \
  GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    git -C "$REPO" commit -q -m 'Add CONTRIBUTING.md, issue templates, and the PR-description rules (#96)'
  # The owner is what the hook checks; nothing is ever fetched.
  git -C "$REPO" remote add origin https://github.com/dbaggott/claude-plugins.git
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD
}
build_repo >/dev/null 2>&1

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

# Act two: the other end of the same workflow. Real reviews the bot filed on a
# real PR, captured once into fixtures/gate-reviews.json — the same shape the
# API returns, with each body trimmed to the first line, which is all the
# formatting below ever shows.
# Written out rather than `clear`, whose bytes come from the terminfo entry and
# the ncurses build — neither pinned, and both differ between a laptop and a
# runner. Scrollback, cursor home, screen.
printf '\033[3J\033[H\033[2J'
say "❯ gh pr view 94 --json reviews"
beat 1.2
printf '\n'
jq -r '
  [.[] | select(.state != "COMMENTED")][:2][]
    | "  \(.user.login)\n    \(.state)  at \(.submitted_at[11:16])\n    \(.body | split("\n")[0] | .[0:70])\n"' \
  "$HERE/fixtures/gate-reviews.json"
beat 5.0
