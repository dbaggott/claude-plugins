Standards now reach the author and the reviewer without either having to think
to go looking. A new always-on rule, **Coding standards stack**, says to load
every standard that applies before writing or reviewing code — the repo's (its
`CLAUDE.md`, any standards doc it names), yours, and
`dnbg-practices:coding-practices` when that plugin is installed — and to hold the
work to all of them, with the project's own winning any disagreement. Authoring
prose that instructs an agent counts as writing code for this.

Nothing loaded `coding-practices` before: it ships no hook, and `git-workflow`
and `issue-workflow` mentioned it only as an optional install. `reviewer` never
mentioned standards at all, so a verdict was judged against whatever the model
brought. Its "Review for" step now names them, and adds that a finding only the
reviewer's own defaults support is a preference rather than a defect.

## Migration
This takes effect on an installed machine as soon as the plugin updates —
`always-on-rules.md` applies to every session. If your repo has standards you did
*not* want applied to agent-facing prose (`SKILL.md`, `CLAUDE.md`), say so in the
document itself; the rule reads them as code.
