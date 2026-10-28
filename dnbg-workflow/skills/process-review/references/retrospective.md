# Process review: retrospectives

Part of the `process-review` skill, which reads retrospectives in batches to
find what recurs; this is the format they are written in. Each role writes one
at its close-out, which its own skill names, whether a session dispatched it or
not: the author once its PR merges or closes, the PR reviewer when its review
ends, both sides of a spec review where it ends, the orchestrator at Stop.
Turns that end earlier, such as the author's at send-to-review, do not write
one. A retrospective records where the **process** hurt one agent on
one issue: the skills, the scripts, the waits. A finding about the code the run
built or touched, such as a gap the design missed or a defect next to the work,
is not a retrospective item: it goes in a findings entry, per
`<skill-dir>/../findings-review/references/entry.md`, written with the report
that lists it.

`<skill-dir>` is the `process-review` skill's **Base directory**, or, for an
agent sent here by path, the directory holding this file's `references/`.

## Where a retrospective goes

In `~/.claude/dnbg-retrospectives/<owner>/<repo>/`, where `<owner>/<repo>` is
the repo the issue lives in. Expand `~` to your home directory and
create the directory if it is missing.

**`~/.claude/dnbg-retrospectives` is the default, not a constant.** If a
`dnbg-workflow` note at session start names a different retrospective root, that
root wins, and `<owner>/<repo>/` goes under it the same way.

Name the file `<YYYY-MM-DD>T<HHMMSS>Z-<n>-<role>.md`, in UTC, where `<n>` is the
issue number and `<role>` is `author`, `reviewer` (a PR review, the `reviewer`
skill), `issue-reviewer` (a spec round, the `issue-reviewer` skill) or
`orchestrator`. The time keeps a second dispatch of the same role from
overwriting the first. A reviewer of a set of issues takes their parent as its
issue, here and in the file's `issue:`. Work under no issue takes its PR: `<n>`
is the PR number and `issue:` the PR's URL.

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

- **`role`** is the `<role>` in the file name.
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

A session that dispatched an agent, such as `orchestrate` or the spec review's
spawned reviewer, collects the agent's retrospective from its final report.
When that report names no retrospective path, or the path it gives does not
exist, continue that agent once with `SendMessage`:

> Write your retrospective now, per your close-out, and reply with the file's
> path.

That continuation is the fallback rather than the plan, because it replays the
agent's whole transcript for one more turn, and a late one finds the cache cold.

A dispatch cut off by a restart of its dispatcher leaves no retrospective, and
so does an agent replaced after dying on an error. Nothing can reach the old
agent, so the loss is not recovered. Say in your own final report which roles
have none.
