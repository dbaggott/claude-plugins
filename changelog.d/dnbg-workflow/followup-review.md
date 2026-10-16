Actionable items in agents' reports no longer vanish when the operator doesn't
act on them at merge time. The author's merge handoff, the reviewer's report and
the orchestrator's Stop now keep each Actionable item as a follow-up entry under
`~/.claude/dnbg-followups/<owner>/<repo>/`, and name its path in the report. The
new `followup_dir` option moves that location.

The new `followup-review` skill sweeps those entries later. It checks each one
against the repo's current default branch, merges duplicates, and proposes
filing, dropping or keeping it, with the issue text drafted. Nothing is filed
until you approve the exact text, and your decision is recorded in the entry so
it never comes up again.
