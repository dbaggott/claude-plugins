# Orchestrate: retrospectives

Part of the `orchestrate` skill. The orchestrator reads this before dispatching,
and every agent it dispatches reads it once, when its part of the run is over:
the author after its post-merge cleanup, the reviewer when its review ends. Turns
that end earlier, such as the author's at send-to-review, do not write one. A
retrospective records where the **process** hurt one agent on one issue: the
skills, the scripts, the waits. The issue's own bugs belong on the issue or the
PR. `process-review` reads retrospectives in batches to find what recurs.

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
keeps a second dispatch of the same role from overwriting the first.

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

Both dispatch recipes in `SKILL.md` carry the request, so it costs no extra
turn. When a final report
arrives without that section, or the path it gives does not exist, continue that
agent once with `SendMessage`:

> Write your retrospective now, per `<skill-dir>/references/retrospective.md`,
> and reply with the file's path.

That continuation is the fallback rather than the plan, because it replays the
agent's whole transcript for one more turn, and a late one finds the cache cold.

A dispatch cut off by an orchestrator restart leaves no retrospective. The new
orchestrator cannot reach the old agent, so the loss is not recovered. Say in
the Stop report which roles have none.

## Your own

At Stop, once the agents' retrospectives are in, write one with
`role: orchestrator` that answers the same prompt about your own run: the
triage, the watches, the escalations, and the dispatches. On a tracking issue
it comes earlier, at `references/closeout.md`'s step 2, so its items reach the
friction log before the closeout disposes of it.

## Fold project-level items into the parent

When the issue is a child of a tracking issue, its body opens with
`Sub-issue of <parent URL>`. Read the run's retrospectives and pick out each
item the parent's closeout should dispose of: anything about this project's
design, its children, or the conventions they share, and any tooling friction
that cost this run real time. Leave out minor plugin-wide friction, which the
files keep for `process-review`.

Add them to the parent body's **Friction log** in one call, a dated bullet per
item naming its source. The parent may live in another repo, so take
`<owner>/<repo>` and `<parent>` from its URL:

```bash
"<skill-dir>/../../scripts/log-row.sh" <owner>/<repo> <parent> --bullet="Friction log" \
  --text='**<YYYY-MM-DD>.** <item> (<role> on <issue URL>)' [--text=…]
```

A sibling's orchestrator may be writing the same parent, and the script confirms
its write survived. `result=ERROR reason=write-lost` means a concurrent write
won every attempt: run it again, which adds only the bullets still missing. On
`section-missing` the parent has nowhere to put them. Say so in the Stop report
instead.
