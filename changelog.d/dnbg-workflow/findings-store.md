Follow-up entries are now **findings entries**. They live in
`~/.claude/dnbg-findings/` instead of `~/.claude/dnbg-followups/`, and the
`followup-review` skill is now `findings-review`. The `followup_dir` setting is
renamed `findings_dir`. A value you set under the old name is still used while
`findings_dir` is empty, and `findings-review` still sweeps entries left in
`~/.claude/dnbg-followups/`. Both fallbacks will be dropped in a later release.
If you had set `followup_dir`, move its entries into the new directory when you
set `findings_dir`, since nothing sweeps a custom old directory after that. Agents now
also write an entry for an observation about the code, not only for an
Actionable item, and for a reviewer's comment the author left unacted on.

A tracking issue's **Friction log** is now its **Findings log**, which holds
what the project found about its own code, drawn from the findings entries the
children's runs wrote. Process friction stays in the retrospectives. At
closeout you decide each finding: file a follow-up issue, drop it, or defer it
to `findings-review`. The closeout no longer files plugin-tooling issues
upstream, and `process-review` no longer reads a tracking issue, only the
retrospective files.

An open tracking issue written before this release still has a
`## Friction log` heading. Rename it to `## Findings log` by hand before its
next orchestrated run, or its findings have nowhere to go.
