# Process review: retrospectives

Part of the `process-review` skill, which reads retrospectives in batches to
find what recurs; this is the format they are written in, and the policy for
whether one is written at all. Each role reaches it at its close-out, which its
own skill names, whether a session dispatched it or not: the author once its PR
merges or closes, the PR reviewer when its review ends, both sides of a spec
review where it ends, the orchestrator at Stop. Turns that end earlier, such as
the author's at send-to-review, write none. A retrospective records where the **process** hurt one agent on
one issue: the skills, the scripts, the waits. A finding about the code the run
built or touched, such as a gap the design missed or a defect next to the work,
is not a retrospective item: it goes in a findings entry, per
`<skill-dir>/../findings-review/references/entry.md`, written with the report
that lists it.

`<skill-dir>` is the `process-review` skill's **Base directory**, or, for an
agent sent here by path, the directory holding this file's `references/`.

## When a retrospective is written

Retrospectives are **off**, unless a `dnbg-workflow` note at session start says
they are on. Either way, answer the prompt below for your run; the state decides
where the answers go.

- **On**: write the file, per the rest of this reference. The report names its
  path in a **Retrospective** section, with a dispatcher's also naming each path
  its agents' reports gave, and says nothing else about process friction. The
  always-on rule's offer to file upstream ("When shipped tooling
  doesn't fit, tell the user") is for friction that stopped the task from
  finishing; the rest waits in the file for `process-review`.
- **Off**: write no file, and give the report no **Retrospective** section.
  Under its **Observations**, put each item that would have gone under
  **Skill wrong or missing** or **Worked around**, both headings whole, as one
  line opening `Friction:`. Nothing from **Slowed or blocked** or **Wished to ask**
  is surfaced. After those lines comes the always-on rule's offer to file
  upstream, with the operator approving the exact text first. With nothing
  under either heading, there are no lines and no offer.

  A dispatched agent has no one to offer to: it puts the lines in its report
  and leaves the offer out. Its dispatcher relays them under its own
  Observations, and the offer is the main session's.

  "Asking the agents for one" below does not apply, and a dispatcher's report
  names no role as having left none: there is no file to ask for.

## Where a retrospective goes

In `~/.claude/dnbg-retrospectives/<owner>/<repo>/`, where `<owner>/<repo>` is
the repo the issue lives in. Expand `~` to your home directory and
create the directory if it is missing.

**`~/.claude/dnbg-retrospectives` is the default, not a constant.** If a
`dnbg-workflow` note at session start names a different retrospective root, that
root wins, and `<owner>/<repo>/` goes under it the same way.

Name the file `<YYYY-MM-DD>T<HHMMSS>Z-<n>-<role>.md`, in UTC, where `<n>` is the
issue number and `<role>` is `author` (a PR, the `git-workflow` skill),
`spec-author` (answering a spec round, `issue-workflow`'s
`references/spec-review-rounds.md`), `reviewer` (a PR review, the `reviewer`
skill), `issue-reviewer` (a spec round, the `issue-reviewer` skill) or
`orchestrator`. The time keeps a second dispatch of the same role from
overwriting the first. A reviewer of a set of issues takes their parent as its
issue, here and in the file's `issue:`. A set with no parent resolved by one
PR (`orchestrate`'s `references/several-issues.md`) names every agent's file for
the set: `issue:` is a YAML list of every issue's URL, ordered by repo and then
number, and the first gives `<owner>/<repo>` and `<n>`. Work under no issue
takes its PR: `<n>` is the PR number and `issue:` the PR's URL.

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

With retrospectives on ("When a retrospective is written"), a session that
dispatched an agent, such as `orchestrate` or the spec review's spawned
reviewer, collects the agent's retrospective from its final report.
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
