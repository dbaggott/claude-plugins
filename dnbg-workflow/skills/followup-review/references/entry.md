# Follow-up review: writing an entry

Part of the `followup-review` skill. Every agent that writes a report with an
**Actionable** section reads this when it writes that report: the author at its
merge handoff and its post-merge report, the reviewer at its report, the
orchestrator at Stop. An entry
keeps one Actionable item after the session ends, so `followup-review` can
decide it later against a fresh tree. Writing one is not filing an issue: filing
stays the operator's call.

`<skill-dir>` is the Base directory of the skill that sent you here.

## Which items get an entry

Each item you list under **Actionable** gets one entry, written as you write the
report, and the report names the entry's path beside the item. Items under
**Observations** get none.

One item has one writer:

- **An item you already wrote an entry for**, in an earlier report on the same
  PR, is not written again. Name the existing path.
- **The reviewer** skips a finding the author didn't take when the author
  follows `git-workflow`, as an orchestrated run's author always does, since the
  author's handoff writes it. On any other PR, such as a teammate's, the reviewer
  writes it too.
- **The orchestrator** writes only the items no agent wrote an entry for. An
  item the reviewer lists without a path is usually one the author's handoff
  lists with one: use that path.

A duplicate that gets through anyway is merged by the sweep.

## Where it goes

In `~/.claude/dnbg-followups/<owner>/<repo>/`, where `<owner>/<repo>` is the repo
the work happened in, which is where the follow-up would be filed. Expand `~` to
your home directory and create the directory if it is missing.

**`~/.claude/dnbg-followups` is the default, not a constant.** If a
`dnbg-workflow` note at session start names a different follow-up root, that
root wins, and `<owner>/<repo>/` goes under it the same way.

Name the file `<YYYY-MM-DD>T<HHMMSS>Z-<n>-<slug>.md`, in UTC, where `<n>` is the
PR number, or the issue number when the report has no single PR, and `<slug>` is
a few lowercase-dashed words naming the problem. One file per item.

## The file

```markdown
---
tags:
  - followup
source: <PR or issue URL>
repo: <owner>/<repo>
observed_at: <commit SHA the claim was checked at>
role: author | reviewer | orchestrator
kind: defect | deferred-finding | follow-up | setup
judgement: clear | unclear
plugin_version: <version>
date: <YYYY-MM-DD>
disposition: open
---

## What

<the problem, with every file:line verified at observed_at>

## Why it matters

## Proposed next step

## Why it was deferred
```

- **`kind`**: `defect` for a bug in code the change did not own, a flaky test
  among them; `deferred-finding` for a review finding left for later;
  `follow-up` for work the change makes possible or needed; `setup` for setup or
  config the merged change needs.
- **`judgement: unclear`** marks an item that needs the operator to think, not
  just approve: the next step is a choice between options, or whether to act at
  all is open.
- **`observed_at`** is the SHA you read the anchors at, usually the PR's head.
  The sweep re-checks the claim against the default branch, and needs to know
  what you saw.
- **`plugin_version`** is the version a `## dnbg-workflow <version>` note at
  session start names. With no such note, read it from the installed plugin's
  manifest with `jq -r .version "<skill-dir>/../../.claude-plugin/plugin.json"`.
  Write `none` only when neither gives one, never a version from memory.

**Write the body for a cold reader weeks from now.** It names files, functions
and lines verified at `observed_at`, not recalled, per `issue-workflow`'s
`references/creating.md`, and references issues and PRs by full URL. It carries
no secrets or tokens, because the sweep quotes it into issue drafts.
