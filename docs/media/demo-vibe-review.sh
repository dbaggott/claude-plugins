#!/usr/bin/env bash
# The same workflow with no issue behind it: the operator works something out
# conversationally and it goes straight to a PR. The draft is what makes that
# comfortable — every one of those iterations lands on a PR nobody is reviewing
# yet, so the reviewer session on the right stays quiet until it's asked for.
#
# A reenactment. See lib-demo.sh.
set -euo pipefail
# shellcheck source=./lib-demo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-demo.sh"

P="https://github.com/dbaggott/claude-plugins/pull/104"

panes "build — session A" "review — session B"

row "${C_USER}❯${C_OFF} let me set the watcher poll curve from an env var"
beat 1.5
row "${C_TOOL}● Skill${C_OFF}  dnbg-workflow:git-workflow"
beat 0.8
row "${C_TOOL}● Bash${C_OFF}   git worktree add .worktrees/poll-curve-config"
beat 1.0
row "${C_TOOL}● Edit${C_OFF}   scripts/lib-poll.sh"
beat 1.4

row "${C_USER}❯${C_OFF} no — keep the default curve, just allow an override"
beat 1.4
row "${C_TOOL}● Edit${C_OFF}   scripts/lib-poll.sh"
beat 0.8
row "${C_TOOL}● Bash${C_OFF}   bats tests/lib-poll.bats ${C_DIM}→ 18 passing${C_OFF}"
beat 1.4

row "${C_USER}❯${C_OFF} ship it"
beat 1.0
row "${C_TOOL}● Bash${C_OFF}   gh pr create --draft"
beat 0.8
row "${C_DIM}         → pull/104 ${C_OFF}${C_WARN}draft${C_OFF}"
beat 1.6

row "" "${C_USER}❯${C_OFF} review $P"
beat 1.4
row "" "${C_TOOL}● Skill${C_OFF}  dnbg-workflow:reviewer"
beat 0.8
row "" "${C_SAY}● pull/104 is still a draft.${C_OFF}"
beat 1.0
picker_lines -s 2 "Review the draft now, or wait for ready?" \
  "Review it now (Recommended)" "Wait until it's ready"
for l in "${PICKER[@]}"; do row "" "$l"; beat 0.35; done
beat 1.4
row "" "${C_TOOL}● Task${C_OFF}   watch-pr.sh 104 --was-draft ${C_DIM}(background)${C_OFF}"
beat 1.6

row "${C_USER}❯${C_OFF} actually call it POLL_CURVE, not CURVE"
beat 1.2
row "${C_TOOL}● Edit${C_OFF}   scripts/lib-poll.sh · git push"
beat 1.0
row "${C_USER}❯${C_OFF} and document it in the README table"
beat 1.2
row "${C_TOOL}● Edit${C_OFF}   README.md · git push"
beat 1.2
row "${C_SAY}  Three pushes, still a draft — no review has${C_OFF}" \
    "${C_DIM}         (quiet — a draft is not review-ready)${C_OFF}"
row "${C_SAY}  fired for any of it.${C_OFF}" ""
beat 2.2

picker_lines "Send pull/104 to review?" \
  "Send to review (Recommended)" "Not yet"
for l in "${PICKER[@]}"; do row "$l" ""; beat 0.35; done
beat 1.4

row "${C_TOOL}● Bash${C_OFF}   gh pr ready 104" "${C_DIM}         ← READY${C_OFF}"
beat 1.3
row "" "${C_TOOL}● Bash${C_OFF}   mint-token.sh · gh pr diff 104 · checks"
beat 0.9
row "" "${C_SAY}● CI is green. Reading its results rather${C_OFF}"
row "" "${C_SAY}  than re-running the suite locally.${C_OFF}"
beat 1.6
row "" "${C_TOOL}● Bash${C_OFF}   gh pr review 104 --request-changes"
beat 1.0
row "${C_BAD}● CHANGES_REQUESTED${C_OFF} · 1 finding" \
    "${C_DIM}         POLL_CURVE unset is untested${C_OFF}"
beat 1.6
row "${C_TOOL}● Edit${C_OFF}   tests/lib-poll.bats · git push" ""
beat 1.2
row "" "${C_TOOL}● Bash${C_OFF}   gh pr review 104 --approve"
beat 1.0
row "${C_OK}● APPROVED — ready to merge.${C_OFF}" \
    "${C_OK}● Approved. Watching until it merges.${C_OFF}"
beat 0.9
row "${C_DIM}  gh pr merge 104 --repo dbaggott/claude-plugins --squash${C_OFF}" ""
beat 0.8
row "${C_TOOL}● Task${C_OFF}   watch-merge.sh 104 ${C_DIM}(background)${C_OFF}" ""
beat 1.8

row "${C_USER}❯ !${C_OFF} gh pr merge 104 --repo dbaggott/claude-plugins --squash"
beat 1.4
row "${C_DIM}   ✓ Squashed and merged pull request #104${C_OFF}" \
    "${C_DIM}         ← MERGED${C_OFF}"
beat 1.8

row "${C_TOOL}● Bash${C_OFF}   git worktree remove .worktrees/poll-curve-config" ""
beat 0.7
row "${C_TOOL}● Bash${C_OFF}   git switch main && git pull --ff-only --prune" ""
beat 0.7
row "${C_TOOL}● Bash${C_OFF}   git branch -D poll-curve-config" ""
beat 1.0
row "${C_SAY}  Cleaned up — nobody asked me to.${C_OFF}" ""
beat 5.0
