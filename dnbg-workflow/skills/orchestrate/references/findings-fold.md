# Orchestrate: your retrospective and the findings fold

Part of the `orchestrate` skill, read once a run's agents have sent their final
reports: at Stop, and under a tracking issue at each child's end
(`references/multi-issue.md`). The retrospective's format, and the agents' side
of it, are in `process-review`'s `references/retrospective.md`, at
`<skill-dir>/../process-review/references/retrospective.md`. `<skill-dir>` is
the `orchestrate` skill's **Base directory**.

## Your own

At Stop, once the agents' retrospectives are in, write one with
`role: orchestrator` that answers that file's prompt about your own run: the
triage, the escalations, and the dispatches.

## Fold the project's findings into the parent

When the issue is a child of a tracking issue, its body opens with
`Sub-issue of <parent URL>`. Take the findings entries this run wrote whose
`project:` is the parent's URL: the paths the author's and the reviewer's
reports name, and your own from Stop.

Only the parent's writer edits its body (`issue-workflow`'s
`references/tracking-issue.md`, "Who writes the body").

**If this session orchestrates the parent** (`references/multi-issue.md`), add
the entries to the parent body's **Findings log** in one call, a dated bullet
per entry naming its source and its path below the findings root, which
leaves your home directory out of the issue. The parent may live in another repo,
so take `<owner>/<repo>` and `<parent>` from its URL:

```bash
"<skill-dir>/../../scripts/log-row.sh" <owner>/<repo> <parent> --bullet="Findings log" \
  --text='**<YYYY-MM-DD>.** <what it found, in one line> (<role> on <source URL>; `<owner>/<repo>/<file>`)' \
  [--text=…] --as=orchestrator
```

A re-run adds only the bullets still missing, so on `write-lost`, `write` or
`issue-query` run it once more. If it fails again, or on `section-missing`,
where the parent has nowhere to put them, say so in the Stop report instead.

**Otherwise**, post the same bullets, each `- ` followed by one `--text` value,
as one comment on the parent whose first line is exactly
`Findings log items from <issue URL>`, from a body file made with `mktemp`:

```bash
"<skill-dir>/../../scripts/as-role.sh" orchestrator <owner>/<repo> -- \
  gh issue comment <parent> --repo <owner>/<repo> --body-file <file>
```

Say in the Stop report that they await folding by the parent's writer.
