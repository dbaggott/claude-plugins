---
name: findings-review
description: Sweep the findings entries agents leave behind for what their reports found about the code — re-check each against the repo's current default branch, merge duplicates, propose filing, dropping or keeping it, and record the operator's decision in the entry. Load when asked to review the findings, sweep the findings entries, review the follow-ups, or decide what to do with deferred Actionable items. Skip for writing an entry, which is `references/entry.md`, for a tracking issue's Findings log at closeout, which is `orchestrate`'s `references/closeout.md`, and for process friction across orchestration runs, which is `process-review`.
---

# Findings review

Each finding about the code an agent reports, such as a deferred review finding,
an out-of-scope defect or setup the merged change needs, is kept as an entry.
This sweeps those entries: it checks each is still true, proposes what to do
with it, and records the operator's decision so no entry is decided twice. One
entry is enough to file; nothing waits for a second.

The entry format is in `references/entry.md`. `<skill-dir>` is the **Base
directory** announced when this skill loads.

## 1. Gather the batch

The batch is every `*.md` file under `~/.claude/dnbg-findings/`, recursively,
whose frontmatter reads `disposition: open`. That root is the default, not a
constant: if a `dnbg-workflow` note at session start names a different findings
root, read that one. The operator may narrow the batch to one repo's
`<owner>/<repo>/` directory, one project's `project:` URL, a date range against
the frontmatter `date`, or `judgement: unclear` only.

Read every entry in the batch in full. One missing `source`, `repo`,
`observed_at` or a `YYYY-MM-DD` `date`, or any of the four body headings, goes
under **Unreadable** in the report with what it lacks, and gets no proposal.

This skill keeps its state in each entry's `disposition` and `swept` fields
(step 5) and writes no report file. `process-review` persists its reports
instead, because a retrospective is never disposed and goes on counting.

## 2. Re-check each entry

Check the claim under **What** against the repo's current default branch, not
against `observed_at` and not against whatever a local checkout has checked out.
Fetch that tree once per repo:

```bash
branch=$(gh api repos/<owner>/<repo> --jq .default_branch)
sha=$(gh api "repos/<owner>/<repo>/commits/$branch" --jq .sha)
"<skill-dir>/../../scripts/fetch-tree.sh" <owner>/<repo> "$sha"
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

An entry whose `source` URL is not on `github.com` gets neither the tree nor the
search. Present it with **not re-checked** and the reason, and propose **keep**.

## 3. Merge entries that describe one problem

Two entries describe one problem when they name the same defect, finding or
missing setup, even worded differently or written by different roles. An
author's and a reviewer's entry for one finding is the expected pair, since
each writes its own. Treat the
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
- dropped: `disposition: "dropped <reason>"`, quoted so a `: ` in the reason
  keeps the frontmatter parseable
- kept: leave `disposition: open`, and add or update `swept: <YYYY-MM-DD>`

Edit only those two fields. A disposed entry stays on disk and never enters a
batch again; a kept one does, with its `swept` date telling the next sweep it was
already seen.

Close with one line per entry: its path and the disposition recorded.

When any issue was filed, ask once for the batch, with the two options of
`issue-workflow`'s `references/filing.md`, "Offer the spec review", in place of
its per-issue question. The prompt is `Review <URL>, <URL> as a set.`, one per
repo the batch was filed in, naming that repo's issues. On "Spec-review it now
(Recommended)", dispatch `issue-reviewer` as
`dnbg-workflow:reviewer-orchestrated` with each prompt, in the background, and
answer the rounds per `issue-workflow`'s `references/spec-review-rounds.md`,
"Spawn the reviewer". On "Not now", end with the prompts to paste.
