# Orchestrate: retrospectives

Part of the `orchestrate` skill. The orchestrator reads this before dispatching,
and every agent it dispatches reads it once, when its part of the run is over:
the author after its post-merge cleanup, the reviewer when its review ends. Turns
that end earlier, such as the author's at send-to-review, do not write one. A
retrospective records where the **process** hurt one agent on one issue: the
skills, the scripts, the waits. `process-review` reads retrospectives in batches
to find what recurs. A finding about the code the run built or touched, such as
a gap the design missed or a defect next to the work, is not a retrospective
item: it goes in a findings entry, per
`<skill-dir>/../findings-review/references/entry.md`, written with the report
that lists it.

`<skill-dir>` is the `orchestrate` skill's **Base directory**, or, for an agent
sent here by path, the directory holding this file's `references/`.

## Where a retrospective goes

In `~/.claude/dnbg-retrospectives/<owner>/<repo>/`, where `<owner>/<repo>` is
the repo the orchestrated issue lives in. Expand `~` to your home directory and
create the directory if it is missing.

**`~/.claude/dnbg-retrospectives` is the default, not a constant.** If a
`dnbg-workflow` note at session start names a different retrospective root, that
root wins, and `<owner>/<repo>/` goes under it the same way.

Name the file `<YYYY-MM-DD>T<HHMMSS>Z-<n>-<role>.md`, in UTC, where `<n>` is the
issue number and `<role>` is `author`, `reviewer` or `orchestrator`. The time
keeps a second dispatch of the same role from overwriting the first. A reviewer
of a set of issues takes their parent as its issue, here and in the file's
`issue:`.

## The prompt

Answer from this run only, one heading per question:

- **Slowed or blocked**: what slowed or blocked you?
- **Skill wrong or missing**: what did a skill tell you that was wrong, missing,
  or contradicted by the tree?
- **Worked around**: what did you work around?
- **Wished to ask**: what did you wish you could have asked?

## The file

```markdown
---
tags:
  - retrospective
  - <role>
role: <role>
issue: <issue URL>
plugin_version: <version>
date: <YYYY-MM-DD>
---

## Slowed or blocked

- <item>

## Skill wrong or missing

- <item>

## Worked around

- <item>

## Wished to ask

- <item>
```

- **All four headings, spelled exactly as above.** `process-review` groups by
  them. Under a heading with nothing to report, write `Nothing.`, since a clean
  run is data too.
- **One bullet per item, naming what it is about**: the skill and step, the
  reference file, or the script (`git-workflow` step 7, `watch-pr.sh`). Where a
  skill said something wrong, quote the line. Patterns are found by grouping on
  these names, so an item that names nothing cannot join one.
- **`plugin_version`** is the version a `## dnbg-workflow <version>` note at
  session start names. With no such note, read it from the installed plugin's
  manifest:

  ```bash
  jq -r .version "<skill-dir>/../../.claude-plugin/plugin.json"
  ```

  Write `none` only when neither gives one. Never write a version from memory,
  since a guessed version reads like a real one.
- **No secrets and no tokens.** The files are local, but `process-review` quotes
  them into issue drafts.

## Asking the agents for one

Each agent's own instructions carry the request, so it costs no extra turn.
When a final report
arrives without that section, or the path it gives does not exist, continue that
agent once with `SendMessage`:

> Write your retrospective now, per your instructions, and reply with the
> file's path.

That continuation is the fallback rather than the plan, because it replays the
agent's whole transcript for one more turn, and a late one finds the cache cold.

A dispatch cut off by an orchestrator restart leaves no retrospective, and so
does an agent replaced after dying on an error. Nothing can reach the old agent,
so the loss is not recovered. Say in the Stop report which roles have none.

## Your own

At Stop, once the agents' retrospectives are in, write one with
`role: orchestrator` that answers the same prompt about your own run: the
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
