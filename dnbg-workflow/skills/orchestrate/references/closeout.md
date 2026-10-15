# Orchestrate: resolving a tracking issue through its closeout PR

Part of the `orchestrate` skill. Read this when `references/multi-issue.md`'s
loop finds every child closed. The parent resolves the way a plain issue does:
one PR closes it, `reviewer`'s issue mode on the parent reviews that PR, and the
operator merges it. You are that PR's author. Step 5 needs the operator's
approval, so this runs in the main session.

The closeout PR writes the project's as-built design into the repo and disposes
of its friction log. The parent's shape and IDs are in `issue-workflow`'s
`references/tracking-issue.md`.

`<skill-dir>` is the **Base directory** announced when this skill loads, or,
with no skill loaded, the directory holding this file's `references/`.

The PR, opened at step 3, is the closeout's record: step 4's runs and step 5's
table go in its description as each finishes, so a restart reads from it which
steps are done.

## 1. Find a predecessor's closeout PR

```bash
"<skill-dir>/../../scripts/pr-sources.sh" <owner>/<repo> <parent>
gh pr view <url> --json state,isDraft,body,closingIssuesReferences
```

Read the per-source fields before treating `count=0` as none, as
`issue-workflow`'s `references/resolving.md` describes. An open PR whose
`closingIssuesReferences` include the parent is a predecessor's closeout PR.
Continue it rather than opening a second, at the first of steps 4 to 6 its
description does not carry; one out of draft resumes at step 6, with a reviewer
dispatched if none is reviewing it. Run step 2 too while its description has
no step-5 table; once it has one, write your retrospective at "Stop" instead,
for `process-review` alone.

## 2. Fold your retrospective

Write your own retrospective, once for the run, per
`references/retrospective.md` with the parent as its issue, and fold its
project-level items into the parent's friction log, so step 5 disposes of them
too.

## 3. Write the as-built design and open the PR

`<doc path>` is `docs/design/<name>.md`, where `<name>` is the parent's title
as a lowercase-dashed slug. If the repo already keeps designs somewhere else
under `docs/`, use that location instead. Open the PR as a draft per
`git-workflow`, self-review included. Its description opens with
`Closes <parent URL>`, so the merge closes the parent.

The doc is the parent body as built, not as planned:

- **Open with one line** linking the tracking issue.
- **Keep** Problem, Goals, Non-goals, Constraints, Requirements, Decisions, Open
  questions, and End-to-end acceptance criteria, with **every ID unchanged**,
  including retired entries and their markings. Children, PRs and commits cite
  these IDs, and once the issue closes the doc is the only place they still
  resolve.
- **Fold the decision log into the entries it changed.** Each entry reads in
  its final form. If a row's reason is not already in the entry's `Because:`,
  add it there. The log itself does not carry over.
- **Settle each open question.** A decided one points at its `D#`. One still
  carrying its default records the default as what was built.
- **Give each `A#` what bears on it**: the merged PRs its `Contributes:` line
  leads to, and its recorded run, by URL, once step 4 has one. Say nothing
  about whether they meet it.
- **Replace the candidate decomposition with a "Where it was built" table**: each
  child's title, its `Covers`, and its merged PR URLs.
- **Drop execution state**: the decision log's states, `Depends on`, claims,
  the friction log, and Required reading.

## 4. Run the criteria no child recorded

Every `A#` met by a run, such as an eval or a live exercise, that no child's
own criteria record is yours to run now. Record each run's output as a section
of the PR description, under the `A#` it is for, and link it from the doc's
`A#`. Running a criterion is not judging it: whether a run meets its `A#` is the
reviewer's call, on this PR.

## 5. Dispose of the friction log

Every friction-log entry gets exactly one disposition: a follow-up issue, or
`Dropped, because <reason>`. Draft them all first, as a table, then show the
operator the table and the exact text of every follow-up before filing any. An
entry about a `dnbg-*` plugin's own tooling is filed upstream under the
always-on "When shipped tooling doesn't fit, tell the user" rule, and that rule
needs the operator's approval of the exact text. Without `AskUserQuestion`, the
table and the follow-up texts are the question in
`<skill-dir>/../issue-workflow/references/delegated.md`, posted on the parent;
file nothing until it is answered.

The table goes in the PR description, not the parent body. It is the friction
log's final state, and the merged PR is what the closed parent links to:

```markdown
| Entry | Disposition |
| --- | --- |
| 2026-10-13: the issue-create hook matches `--help` | <follow-up issue URL> |
| 2026-10-14: author side of a set review is manual | Dropped, because the multi-issue orchestrator now does it |
```

Put the approved table in the description first, then file each approved
follow-up per `issue-workflow`'s `references/creating.md`, writing its URL into
its row as soon as it is filed. A row still without a URL on resume is searched
for by its title before it is filed. A follow-up that a review round turns into
a drop is closed as not planned, citing the round.

## 6. Send it to review, and see it through

Send it to review per `git-workflow`'s "After opening a draft PR". When it is
out of draft, dispatch `reviewer` on the parent, in the background:

> Act as the reviewer on `<parent URL>`, in `reviewer`'s issue mode. It is a
> tracking issue, so grade the whole project on its closeout PR. You were
> dispatched by an orchestrator, so follow `issue-workflow`'s
> `references/delegated.md` wherever a skill asks the operator something. When
> your review ends, write a retrospective per
> `<skill-dir>/references/retrospective.md`, and end your final report with a
> **Retrospective** section giving the file's path.

Its review arrives on the PR, so handle every round as an author does, per
`git-workflow`'s `references/review-rounds.md`. A finding on an `A#` with no
recorded run is answered by running it and recording it, as in step 4.

A finding this PR cannot answer, such as unbuilt work that a new child would
own, is an escalation, as `references/multi-issue.md`'s "Triage and the log"
describes: what to build next is the operator's call. When the answer adds or
reopens a child, return the PR to draft with `gh pr ready <pr> --undo` and go
back to the loop. It reaches this file again at `open=0`, where step 1 finds
the PR and you bring its doc up to date before sending it back to review.

When the review is clean, give the operator the merge handoff per
`git-workflow`'s `references/merge.md`. Never merge. The merge closes the
parent. Run `git-workflow`'s post-merge cleanup, then go to
`references/multi-issue.md`'s "Stop", once the reviewer's final report is in.
If the PR closes unmerged, ask the operator whether to open a new one or stop.
