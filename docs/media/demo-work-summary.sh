#!/usr/bin/env bash
# Turning a week of merged PRs into a recap someone else can read.
#
# Condensed from a real session (2026-08-11) — the commands, the counts, the
# three-axis question and the operator's actual answer to it ("do two, one for
# teammates and one for leadership") are what happened. Two beats matter: the
# gather reads PR *descriptions* rather than diffs, and audience is settled
# before a word is written.
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
say "${C_TOOL}● Bash${C_OFF}   gh search prs --owner dbaggott,qhcorp --author dbaggott \\"
say "${C_TOOL}       ${C_OFF}     --merged-at 2026-08-10T04:00:00-07:00.."
say "${C_DIM}  ⎿ 14 merged PRs across 6 repos${C_OFF}"
beat 1.4

say "${C_SAY}● Reading the descriptions, not the diffs. A PR body here is the${C_OFF}"
say "${C_SAY}  as-built record, so the recap is mostly already written down.${C_OFF}"
beat 1.6
say "${C_TOOL}● Bash${C_OFF}   gh pr view --json body,closingIssuesReferences ${C_DIM}×14${C_OFF}"
say "${C_DIM}  ⎿ 2 issues closed · 1 filed${C_OFF}"
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
say "  *Landfall: scraping is auditable, bugs are one-press reportable*"
say "  Two artifacts, two lifetimes: a provenance trace (which rule won"
say "  each field, no page content, kept) and evidence (the bundle plus a"
say "  page capture, 90-day expiry)."
beat 1.2
say "  Its *first real use* found and fixed a live bug: FB items whose main"
say "  slot is a video render every photo as a 36px thumb, so the size rule"
say "  matched nothing."
beat 1.2
say "  ${C_WARN}Caveat:${C_OFF} exercised end to end in a real browser, but the AWS"
say "  delivery half has not run against a deployed stack."
beat 1.8

printf '\n'
say "${C_USER}  For leadership${C_OFF}"
beat 0.5
say "  *Bug reports from our listing scraper now reach the person who can"
say "  fix them.* A scraping bug used to be unreproducible by construction —"
say "  the page that caused it was gone by the time anyone noticed. Reports"
say "  now capture how the data was extracted and, for 90 days, the page it"
say "  came from. It found and fixed a real listing-import bug on its first"
say "  live use. The in-browser path is proven end to end; the cloud half is"
say "  built and reviewed but has not yet run against the deployed"
say "  environment."
beat 2.0

printf '\n'
say "${C_SAY}  Same 14 PRs, same caveats. Different altitude.${C_OFF}"
beat 5.0
