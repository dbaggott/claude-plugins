#!/usr/bin/env bash
# One prompt drives one issue to a merged PR: the session claims the issue,
# dispatches an author and a reviewer as subagents, answers the question the
# issue's body settles, brings the operator the one it does not, and stops when
# the PR merges. Two beats matter: the answered question never reaches the
# operator, and both answers are logged on the issue.
#
# A reenactment. See lib-demo.sh.
set -euo pipefail
# shellcheck source=./lib-demo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-demo.sh"

say() { printf '%s\n' "$1"; }

U="https://github.com/dbaggott/claude-plugins/issues/42"

say "${C_USER}❯${C_OFF} orchestrate the resolution of $U"
beat 1.4

say "${C_TOOL}● Skill${C_OFF}(dnbg-workflow:orchestrate)"
beat 0.8
say "${C_TOOL}● Bash${C_OFF}   fetch-issue-set.sh · claim-issue.sh --claim · pr-sources.sh"
say "${C_DIM}  ⎿ no sub-issues · claimed · no PR in flight${C_OFF}"
beat 1.3
say "${C_SAY}● Read the body and its comments. Its approach holds up, so I'll dispatch.${C_OFF}"
beat 1.4
say "${C_TOOL}● Agent${C_OFF}  author: resolve #42, send it to review, auto-handle rounds ${C_DIM}(background)${C_OFF}"
say "${C_TOOL}● Bash${C_OFF}   watch-issue.sh 42 --role=orchestrator ${C_DIM}(background)${C_OFF}"
beat 1.6

say "${C_DIM}  ← author: Delegated question: retry the fetch, or fail fast?${C_OFF}"
beat 1.2
say "${C_SAY}● The body's open question states a default — fail fast — so that one is${C_OFF}"
say "${C_SAY}  answered without you.${C_OFF}"
beat 1.4
say "${C_TOOL}● Bash${C_OFF}   gh issue comment 42 ${C_DIM}— Decision log: 42-D1 — decided${C_OFF}"
say "${C_TOOL}● SendMessage${C_OFF} author: fail fast, per the row"
beat 1.6

say "${C_DIM}  ← author: Delegated question: the flag also changes --help output. Ship it?${C_OFF}"
beat 1.2
say "${C_SAY}● User-visible behavior the issue doesn't cover — that's yours to decide.${C_OFF}"
say "${C_TOOL}● Bash${C_OFF}   gh issue comment 42 ${C_DIM}— Decision log: 42-D2 — proposed${C_OFF}"
beat 1.2

printf '\n'
picker_lines "Document the new flag in --help?" \
  "Yes, list it (Recommended)" "No, keep it hidden"
for l in "${PICKER[@]}"; do say "$l"; beat 0.35; done
beat 1.5

say "${C_TOOL}● Bash${C_OFF}   gh issue comment 42 ${C_DIM}— Decision log: 42-D2 — decided${C_OFF}"
say "${C_TOOL}● Bash${C_OFF}   gh issue edit 42 ${C_DIM}— decision promoted into the body${C_OFF}"
say "${C_TOOL}● SendMessage${C_OFF} author: list it, per the row"
beat 1.6

say "${C_DIM}  ← author: sent pull/118 to review${C_OFF}"
say "${C_DIM}  ← watch-pr.sh 118: READY${C_OFF}"
say "${C_TOOL}● Agent${C_OFF}  reviewer: review #42 in issue mode ${C_DIM}(background)${C_OFF}"
beat 1.6
say "${C_DIM}  ← watch-pr.sh 118: ACTIVITY — CHANGES_REQUESTED; the author is on it${C_OFF}"
beat 1.2
say "${C_DIM}  ← watch-pr.sh 118: ACTIVITY — APPROVED${C_OFF}"
say "${C_TOOL}● Bash${C_OFF}   pr-verdict.sh 118"
say "${C_DIM}  ⎿ verdict=APPROVED at_head=1 reviewed_after_head=1${C_OFF}"
say "${C_OK}● pull/118 is approved at its head and ready for you to merge.${C_OFF}"
beat 2.2

say "${C_DIM}  ← watch-pr.sh 118: CLOSED state=MERGED${C_OFF}"
say "${C_DIM}  ← author: cleaned up · retrospective written${C_OFF}"
say "${C_DIM}  ← reviewer: review ended · retrospective written${C_OFF}"
beat 1.4

printf '\n'
say "${C_USER}Summary${C_OFF}"
say "  pull/118 merged. Two questions: one answered from the body, one escalated."
say "${C_USER}Observations${C_OFF}"
say "  Three retrospectives written: author, reviewer, orchestrator."
say "${C_USER}Actionable${C_OFF}"
say "  Nothing outstanding."
beat 5.0
