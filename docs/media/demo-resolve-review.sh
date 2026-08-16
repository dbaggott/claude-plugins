#!/usr/bin/env bash
# Two sessions on one issue, side by side: the left resolves it, the right is
# assigned as its reviewer. The point of the split is the handoff — the reviewer
# holds back while the PR is a draft, and starts the moment it is marked ready.
#
# A reenactment. See lib-demo.sh for what that means and what is verbatim.
set -euo pipefail
# shellcheck source=./lib-demo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-demo.sh"

U="https://github.com/dbaggott/claude-plugins/issues/17"

panes "resolve — session A" "review — session B"

row "${C_USER}❯${C_OFF} resolve $U"
beat 1.4
row "" "${C_USER}❯${C_OFF} review $U"
beat 1.4

row "${C_TOOL}● Skill${C_OFF}  dnbg-workflow:issue-workflow"
beat 0.7
row "" "${C_TOOL}● Skill${C_OFF}  dnbg-workflow:reviewer"
beat 1.0

row "${C_SAY}● Checking the issue isn't already claimed —${C_OFF}" \
    "${C_TOOL}● Bash${C_OFF}   mint-token.sh dbaggott"
row "${C_SAY}  assignee, assigned:* labels, and linked PRs.${C_OFF}" \
    "${C_DIM}         token minted: agent-reviewer-dbaggott[bot]${C_OFF}"
beat 1.2
row "${C_TOOL}● Bash${C_OFF}   gh issue view 17 · gh api .../timeline" ""
beat 0.9
row "${C_DIM}         unclaimed — safe to start${C_OFF}" \
    "${C_SAY}● No PR resolves this issue yet — I'll wait.${C_OFF}"
beat 1.4

row "${C_TOOL}● Bash${C_OFF}   gh issue edit --add-assignee @me --add-label" ""
row "${C_DIM}         assigned:agent-session · claim comment posted${C_OFF}" ""
beat 1.4

row "${C_TOOL}● Bash${C_OFF}   git worktree add .worktrees/readme-front-page" \
    "${C_TOOL}● Task${C_OFF}   watch-issue.sh 17 --role=reviewer ${C_DIM}(background)${C_OFF}"
beat 1.3
row "${C_TOOL}● Edit${C_OFF}   README.md, docs/*.md" ""
beat 1.0
row "${C_TOOL}● Bash${C_OFF}   gh pr create --draft" ""
beat 0.9
row "${C_DIM}         → pull/98 ${C_OFF}${C_WARN}draft${C_OFF}" \
    "${C_DIM}         ← ACTIVITY: pull/98 appeared${C_OFF}"
beat 1.5

row "${C_SAY}● One departure from the issue, before review:${C_OFF}" \
    "${C_SAY}● Still a draft — the author's signal to${C_OFF}"
row "${C_SAY}  it specifies a poster; self-hosting has no click.${C_OFF}" \
    "${C_SAY}  hold off, so I won't review it yet.${C_OFF}"
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
beat 0.9
row "${C_SAY}  When the review lands I'll fetch the verdict, the${C_OFF}" ""
row "${C_SAY}  inline comments and the unresolved threads, summarize${C_OFF}" ""
row "${C_SAY}  them, and ask how you want the round handled.${C_OFF}" ""
beat 2.0

row "" "${C_TOOL}● Bash${C_OFF}   gh pr diff 98 · statusCheckRollup"
beat 0.9
row "" "${C_SAY}● Reviewing against the issue's acceptance criteria.${C_OFF}"
beat 1.5
row "" "${C_TOOL}● Bash${C_OFF}   gh pr review 98 --request-changes"
beat 0.9
row "${C_DIM}         ← ACTIVITY${C_OFF}" "${C_DIM}         2 inline findings posted as the bot${C_OFF}"
beat 1.5

row "${C_BAD}● CHANGES_REQUESTED${C_OFF} · 2 findings" ""
row "${C_DIM}    forge hedge doesn't name the open confirmations${C_OFF}" ""
row "${C_DIM}    demo caption overclaims what is captured${C_OFF}" ""
beat 1.8

picker_lines "How should I handle this round?" \
  "Auto-handle all rounds (Recommended)" "Address this round only" "Leave PR sitting"
for l in "${PICKER[@]}"; do row "$l" ""; beat 0.35; done
beat 1.5

row "${C_TOOL}● Edit${C_OFF}   docs/forge-support.md · README.md" ""
row "${C_TOOL}● Bash${C_OFF}   git push · threads replied and resolved" ""
beat 1.3
row "" "${C_DIM}         ← COMMITS: re-reviewing${C_OFF}"
beat 1.2
row "" "${C_TOOL}● Bash${C_OFF}   gh pr review 98 --approve"
beat 1.0
row "${C_OK}● APPROVED at 5b52654 — ready to merge.${C_OFF}" \
    "${C_OK}● Approved. Watching until it merges.${C_OFF}"
beat 0.9
row "${C_DIM}  gh pr merge 98 --repo dbaggott/claude-plugins --squash${C_OFF}" ""
beat 0.8
row "${C_TOOL}● Task${C_OFF}   watch-pr.sh 98 --role=author ${C_DIM}(background)${C_OFF}" ""
row "${C_SAY}  Merge whenever — I'll clean up when it lands.${C_OFF}" ""
beat 5.0
