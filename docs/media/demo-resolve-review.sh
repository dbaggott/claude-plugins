#!/usr/bin/env bash
# Two sessions on one issue, side by side: the left resolves it, the right is
# assigned as its reviewer. The point of the split is the handoff — the reviewer
# holds back while the PR is a draft, and starts the moment it is marked ready.
#
# A reenactment. See lib-demo.sh for what that means and what is verbatim.
set -euo pipefail
# shellcheck source=./lib-demo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-demo.sh"

I="issues/17"

panes "resolve — session A" "review — session B"

row "${C_USER}❯${C_OFF} resolve github.com/dbaggott/claude-plugins/$I"
beat 1.4
row "" "${C_USER}❯${C_OFF} you review that same issue"
beat 1.4

row "${C_TOOL}● Skill${C_OFF}  dnbg-workflow:issue-workflow"
beat 0.7
row "" "${C_TOOL}● Skill${C_OFF}  dnbg-workflow:reviewer"
beat 1.0

row "${C_TOOL}● Bash${C_OFF}   gh issue view 17 --json assignees,labels" \
    "${C_TOOL}● Bash${C_OFF}   mint-token.sh dbaggott"
beat 0.9
row "${C_DIM}         unclaimed — no assignee, no assigned:* label${C_OFF}" \
    "${C_DIM}         token minted for agent-reviewer-dbaggott[bot]${C_OFF}"
beat 1.2

row "${C_TOOL}● Bash${C_OFF}   gh issue edit 17 --add-assignee @me \\" ""
row "${C_TOOL}       ${C_OFF}     --add-label assigned:agent-session" \
    "${C_SAY}● No PR resolves this issue yet.${C_OFF}"
beat 0.9
row "${C_DIM}         claimed, with a session-stamped comment${C_OFF}" \
    "${C_SAY}  I'll wait for one to appear.${C_OFF}"
beat 1.4

row "${C_TOOL}● Bash${C_OFF}   git worktree add .worktrees/readme-front-page" \
    "${C_TOOL}● Task${C_OFF}   watch-pr.sh --issue 17 ${C_DIM}(background)${C_OFF}"
beat 1.3
row "${C_TOOL}● Edit${C_OFF}   README.md, docs/*.md" ""
beat 1.0
row "${C_TOOL}● Bash${C_OFF}   gh pr create --draft" ""
beat 0.9
row "${C_DIM}         → pull/98 ${C_OFF}${C_WARN}draft${C_OFF}" \
    "${C_DIM}         ← ACTIVITY: pull/98 appeared${C_OFF}"
beat 1.5

row "${C_SAY}● One departure from the issue, before this${C_OFF}" \
    "${C_SAY}● It's still a draft — that's the author's${C_OFF}"
row "${C_SAY}  goes to review: it specifies a poster image,${C_OFF}" \
    "${C_SAY}  signal to hold off, so I won't review it yet.${C_OFF}"
row "${C_SAY}  but self-hosting removes the click entirely.${C_OFF}" ""
beat 1.6
row "" "${C_TOOL}● Task${C_OFF}   watch-pr.sh 98 --was-draft ${C_DIM}(background)${C_OFF}"
beat 1.6

picker_lines "Send pull/98 to review?" \
  "Send to review (Recommended)" "Not yet"
for l in "${PICKER[@]}"; do row "$l" ""; beat 0.35; done
beat 1.5

row "${C_TOOL}● Bash${C_OFF}   gh pr ready 98" ""
beat 0.8
row "${C_TOOL}● Task${C_OFF}   watch-pr.sh 98 ${C_DIM}(background)${C_OFF}" \
    "${C_DIM}         ← READY${C_OFF}"
beat 1.4

row "" "${C_TOOL}● Bash${C_OFF}   gh pr diff 98 · statusCheckRollup"
beat 0.9
row "" "${C_SAY}● Reviewing against the issue's acceptance${C_OFF}"
row "" "${C_SAY}  criteria, not just the diff.${C_OFF}"
beat 1.5
row "" "${C_TOOL}● Bash${C_OFF}   gh pr review 98 --request-changes"
beat 0.9
row "${C_DIM}         ← ACTIVITY${C_OFF}" "${C_DIM}         2 inline findings posted as the bot${C_OFF}"
beat 1.5

row "${C_BAD}● CHANGES_REQUESTED${C_OFF} · 2 findings" ""
beat 1.2
row "${C_TOOL}● Edit${C_OFF}   docs/forge-support.md" ""
row "${C_TOOL}● Bash${C_OFF}   git push · threads replied and resolved" ""
beat 1.3
row "" "${C_DIM}         ← COMMITS: re-reviewing${C_OFF}"
beat 1.2
row "" "${C_TOOL}● Bash${C_OFF}   gh pr review 98 --approve"
beat 1.0
row "${C_OK}● APPROVED at 5b52654 — ready to merge.${C_OFF}" \
    "${C_OK}● Approved. Watching until it merges.${C_OFF}"
beat 1.0
beat 5.0
