#!/usr/bin/env bash
# Turning a week of merged PRs into a recap someone else can read.
#
# Built from this repo's own history. The PR, repo and issue counts are real for
# the window shown, and the three-axis question and its answer ("do two, one for
# teammates and one for leadership") are what the skill actually asks. The recap
# prose is written for the demo. Two beats matter: the gather reads PR
# *descriptions* rather than diffs, and audience is settled before a word is
# written.
#
# A reenactment. See lib-demo.sh.
set -euo pipefail
# shellcheck source=./lib-demo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-demo.sh"

say() { printf '%s\n' "$1"; }

printf '%s❯%s Summarize the work I'"'"'ve done this week\n' "$C_USER" "$C_OFF"
beat 1.4

say "${C_TOOL}● Skill${C_OFF}(dnbg-work-summary:work-summary)"
beat 0.9
say "${C_TOOL}● Bash${C_OFF}   date '+%Y-%m-%d %A %z %Z' · gh api user --jq .login"
say "${C_DIM}  ⎿ 2026-08-11 Tuesday -0700 PDT · dbaggott${C_OFF}"
beat 1.2
say "${C_TOOL}● Bash${C_OFF}   gh search prs --owner dbaggott --author dbaggott \\"
say "${C_TOOL}       ${C_OFF}     --merged-at 2026-08-10T04:00:00-07:00.."
say "${C_DIM}  ⎿ 28 merged PRs across 6 repos${C_OFF}"
beat 1.4

say "${C_SAY}● Reading the descriptions, not the diffs. A PR body here is the${C_OFF}"
say "${C_SAY}  as-built record, so the recap is mostly already written down.${C_OFF}"
beat 1.6
say "${C_TOOL}● Bash${C_OFF}   gh pr view --json body,closingIssuesReferences ${C_DIM}×28${C_OFF}"
say "${C_DIM}  ⎿ 15 issues closed · 10 filed${C_OFF}"
beat 1.6

printf '\n'
picker_lines "Who's reading this recap?" \
  "Teammates" "Manager or lead" "Leadership" "Just me"
for l in "${PICKER[@]}"; do say "$l"; beat 0.3; done
beat 0.8
say "${C_DIM}  → \"do two — one for teammates, one for leadership\"${C_OFF}"
say "${C_DIM}     format: Slack · detail: Standard${C_OFF}"
beat 2.0

printf '\n'
say "${C_USER}  For teammates${C_OFF}"
beat 0.5
say "  *The prompts are instruction again, not their own history*"
say "  Four trimming passes over the skills, then an audit for what they"
say "  missed: descriptions cut back to routing information, and"
say "  issue-workflow split along its create/resolve seam so a resolver"
say "  stops loading the half about filing."
beat 1.2
say "  The duplicated gh/jq/GraphQL blocks moved out of the skill prose"
say "  into scripts/. shellcheck covers scripts/ and covers nothing inside"
say "  a .md, so every one of those blocks was untested by construction."
beat 1.2
say "  ${C_WARN}Caveat:${C_OFF} judged by reading. Nothing asserts a skill stays trimmed."
beat 1.8

printf '\n'
say "${C_USER}  For leadership${C_OFF}"
beat 0.5
say "  *The workflow got cheaper to run and harder to contradict itself.*"
say "  Every session loads these prompts before it does any work, and they"
say "  had accumulated their own change history — text explaining why"
say "  something used to be different rather than instructing. Cutting it"
say "  means less read per session and fewer places for two instructions to"
say "  disagree. The shell the skills hand out now lives in real script"
say "  files, so it is linted and tested rather than copy-pasted prose."
beat 2.0

printf '\n'
say "${C_SAY}  Same 28 PRs, same caveats. Different altitude.${C_OFF}"
beat 5.0
