# Findings review: writing an entry

Part of the `findings-review` skill. Every agent that writes a report with an
**Actionable** or **Observations** section reads this when it writes that
report: the author at its merge handoff and its post-merge report, the reviewer
at its handoff and its close-out, the orchestrator at Stop. An entry keeps one finding after the
session ends, so `findings-review`, or a tracking issue's closeout, can decide
it later against a fresh tree. Writing one is not filing an issue: filing stays
the operator's call.

`<skill-dir>` is the Base directory of the skill that sent you here.

## Which items get an entry

Each item you list under **Actionable** gets one entry, and so does each item
under **Observations** that is a finding about the code the run built or
touched: a gap the design missed, a convention the change diverged from, a
missing test, a defect seen next to the work. An observation about the run
itself, such as a timing or what you checked and found handled, gets none.
Write the entry as you write the report, and name its path beside the item.

Process friction, such as a skill that did not fit or a script that got in the
way, is not a finding. It goes in a retrospective, when the run asks for one.

Who writes an entry:

- **An item you already wrote an entry for**, in an earlier report on the same
  PR, is not written again. Name the existing path.
- **The reviewer** writes one for every finding it raised that stands
  unaddressed at its handoff, or at its close-out on a PR it gave no handoff,
  except one the author declined in a reply saying the operator told it to.
- **The author** writes one at its merge handoff for every finding it declined,
  as `<skill-dir>/../git-workflow/references/merge.md`'s "The report that goes
  with the command" has it, except one it declined because the operator told it
  to.
- **The orchestrator** writes only the items no agent wrote an entry for. An
  item the reviewer lists without a path is usually one the author's handoff
  lists with one: use that path.

An operator-ordered decline gets an entry from neither side: the operator has
already made the decision an entry would put in front of them, and the report
names it under Observations instead. Any other finding the author declined and
the reviewer still holds gets an entry from each: that is the expected pair,
which the sweep merges as one item, as it does any other duplicate.

## Where it goes

In `~/.claude/dnbg-findings/<owner>/<repo>/`, where `<owner>/<repo>` is the repo
the work happened in, which is where a follow-up would be filed. Expand `~` to
your home directory and create the directory if it is missing.

**`~/.claude/dnbg-findings` is the default, not a constant.** If a
`dnbg-workflow` note at session start names a different findings root, that
root wins, and `<owner>/<repo>/` goes under it the same way.

Name the file `<YYYY-MM-DD>T<HHMMSS>Z-<n>-<slug>.md`, in UTC, where `<n>` is the
PR number, or the issue number when the report has no single PR, and `<slug>` is
a few lowercase-dashed words naming the problem. One file per item.

## The file

```markdown
---
tags:
  - finding
source: <PR or issue URL>
repo: <owner>/<repo>
project: <tracking issue URL>
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

- **`project`** is the URL of the tracking issue the work is under, which is
  how its closeout finds the entry. The issue the work resolves names it as its
  `parent` (`gh issue view <n> --repo <owner>/<repo> --json parent`). Work on
  the tracking issue itself, such as its closeout PR or a systemic finding its
  orchestrator raises, takes the tracking issue's own URL. Leave the line out for work
  under no tracking issue.
- **`kind`**: `defect` for a bug in code the change did not own, a flaky test
  among them; `deferred-finding` for a review finding left for later, or an
  observation about the code nobody acted on; `follow-up` for work the change
  makes possible or needed; `setup` for setup or config the merged change needs.
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
