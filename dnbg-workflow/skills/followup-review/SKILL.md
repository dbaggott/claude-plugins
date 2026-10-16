---
name: followup-review
description: Sweep the follow-up entries agents leave behind for each Actionable item in their reports — re-check each against the repo's current default branch, merge duplicates, propose filing, dropping or keeping it, and record the operator's decision in the entry. Load when asked to review the follow-ups, sweep the follow-up entries, or decide what to do with deferred Actionable items. Skip for writing an entry, which is `references/entry.md`, and for process friction across orchestration runs, which is `process-review`.
---

# Follow-up review

An Actionable item in a report is something the operator may want done: a
deferred finding, an out-of-scope defect, setup the merged change needs. Each one
is kept as an entry when the report is written, because the operator is often not
in a state to decide it then. This sweeps those entries later: it checks each is
still true, proposes what to do with it, and records the operator's decision so
no entry is decided twice. One entry is enough to file; nothing waits for a
second.

The entry format is in `references/entry.md`. `<skill-dir>` is the **Base
directory** announced when this skill loads.

## 1. Gather the batch

The batch is every `*.md` file under `~/.claude/dnbg-followups/`, recursively,
whose frontmatter reads `disposition: open`. That root is the default, not a
constant: if a `dnbg-workflow` note at session start names a different follow-up
root, read that one. The operator may narrow the batch to one repo's
`<owner>/<repo>/` directory, a date range against the frontmatter `date`, or
`judgement: unclear` only.

Read every entry in the batch in full. One missing `source`, `repo` or
`observed_at`, or any of the four body headings, goes under **Unreadable** in
the report with what it lacks, and gets no proposal.

## 2. Re-check each entry

Check the claim under **What** against the repo's current default branch, not
against `observed_at`. Read the files in the checkout when you are standing in
that repo, after `git fetch origin`; otherwise fetch the tree once per repo:

```bash
"<skill-dir>/../../scripts/fetch-tree.sh" <owner>/<repo> <default-branch-sha>
```

Remove the directory it prints once the sweep is done. Then find the entry in one
of three states:

- **Still true**: the anchors hold what the entry says, or what moved still
  shows the problem.
- **Already fixed**: the default branch no longer has the problem. Name the
  commit or PR that fixed it when you can find it.
- **Already filed**: an issue in the repo covers it, open or closed. Search with
  `gh issue list --repo <owner>/<repo> --state all --search "<keywords>"`, using
  the entry's file names and the problem's terms, and read any candidate before
  deciding it covers the entry.

An entry for a repo not on `github.com` cannot be searched for an existing
issue: say so, and judge it on the tree alone.

## 3. Merge entries that describe one problem

Two entries describe one problem when they name the same defect, finding or
missing setup, even worded differently or written by different roles. Treat the
group as one item from here on, and record the decision on every entry in it.

## 4. Propose a disposition and present them

Each entry or group gets one proposal:

- **File**, for a still-true item: the issue's exact title and body, drafted per
  `issue-workflow`'s `references/creating.md`, with its anchors re-verified at the
  default branch rather than copied from the entry.
- **Drop**, with the reason and its evidence: fixed (by what), filed (the issue
  URL), or not worth doing (why).
- **Keep**, for an item still true but not yet worth an issue, or one waiting on
  something named.

Present clear entries first, then unclear ones. For each, give the entry's path,
its `source`, a line on what it says, what the re-check found, and the proposal,
with any drafted issue in full. Then ask the operator for a decision on each, with
`AskUserQuestion` offering **file**, **drop** and **keep**, the proposed one first.
Choosing **file** approves the drafted text; an edited draft is new text, which
needs approval again.

Without `AskUserQuestion`, as in a subagent, end with the report as it stands
and record nothing: a disposition is the operator's decision, and a dispatcher's
message does not give it.

## 5. Record each decision

File an approved issue with `issue-workflow`, in the entry's `repo`. These are the
operator's own repos, so the always-on rule about filing upstream does not apply;
the approval of the exact text above still does.

Then set the entry's frontmatter, on every entry in a merged group:

- filed: `disposition: filed <issue URL>`
- dropped: `disposition: dropped <reason>`
- kept: leave `disposition: open`, and add or update `swept: <YYYY-MM-DD>`

Edit only those two fields. A disposed entry stays on disk and never enters a
batch again; a kept one does, with its `swept` date telling the next sweep it was
already seen.

Close with one line per entry: its path and the disposition recorded.
