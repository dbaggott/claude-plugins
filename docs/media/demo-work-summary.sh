#!/usr/bin/env bash
# Turning a week of merged PRs into a recap someone else can read. The point of
# the demo is the step in the middle: the skill settles audience, format and
# detail before writing, because those three change the artifact more than the
# underlying work does.
#
# A reenactment. See lib-demo.sh.
set -euo pipefail
# shellcheck source=./lib-demo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-demo.sh"

say() { printf '%s\n' "$1"; }

printf '%s❯%s summarize what shipped this week\n' "$C_USER" "$C_OFF"
beat 1.5

say "${C_TOOL}● Skill${C_OFF}  dnbg-work-summary:work-summary"
beat 1.0
say "${C_TOOL}● Bash${C_OFF}   gh search prs --merged --author @me --merged-at '>=2026-08-04'"
beat 0.9
say "${C_TOOL}● Bash${C_OFF}   gh search issues --author @me --created '>=2026-08-04'"
beat 0.9
say "${C_DIM}         6 PRs merged · 2 issues filed${C_OFF}"
beat 1.3
say "${C_SAY}● Reading the descriptions, not the diffs — the recap is${C_OFF}"
say "${C_SAY}  about outcomes, and a diff does not state one.${C_OFF}"
beat 1.8

printf '\n'
picker_lines "Who is reading this?" \
  "Teammates" "Manager or lead" "Leadership" "Just me"
for l in "${PICKER[@]}"; do say "$l"; beat 0.3; done
beat 1.6

printf '\n'
say "${C_DIM}  format: Slack   detail: Standard${C_OFF}"
beat 1.6

printf '\n'
say "${C_USER}  This week${C_OFF}"
beat 0.6
say "  • README is now a front page plus ${C_DIM}docs/${C_OFF} — a stranger can tell"
say "    what this is without reading 570 lines. ${C_DIM}pull/98${C_OFF}"
beat 0.9
say "  • The reviewer bot no longer misses thread-only replies,"
say "    which was silently dropping review rounds. ${C_DIM}pull/91${C_OFF}"
beat 0.9
say "  • Watchers back off while a PR is quiet, so a long wait"
say "    stops costing a wake-up a minute. ${C_DIM}pull/89${C_OFF}"
beat 1.0
say "${C_DIM}  Also filed: the symlink bug in check-worktree (issues/97)${C_OFF}"
beat 1.6

printf '\n'
say "${C_SAY}  Same six PRs, different audience, different recap.${C_OFF}"
beat 5.0
