# Orchestrate: resolving a tracking issue through its closeout PR

Part of the `orchestrate` skill. Read this when `references/multi-issue.md`'s
loop finds every child closed. The parent resolves the way a plain issue does:
one PR closes it, `reviewer`'s issue mode on the parent reviews that PR, and the
operator merges it. You are that PR's author. Step 3 needs the operator's
approval, so this runs in the main session.

The closeout PR writes the project's as-built design into the repo and disposes
of its friction log. The parent's shape and IDs are in `issue-workflow`'s
`references/tracking-issue.md`.

`<skill-dir>` is the **Base directory** announced when this skill loads, or,
with no skill loaded, the directory holding this file's `references/`.

## 1. Find a predecessor's closeout PR

```bash
"<skill-dir>/../../scripts/pr-sources.sh" <owner>/<repo> <parent>
gh pr view <url> --json state,isDraft,closingIssuesReferences
```

Read the per-source fields before treating `count=0` as none, as
`issue-workflow`'s `references/resolving.md` describes. An open PR whose
`closingIssuesReferences` include the parent is a predecessor's closeout PR.
Continue it rather than opening a second: a draft resumes at whichever of steps
2 to 4 its description does not yet carry, and one out of draft resumes at step
5, with a reviewer dispatched if none is reviewing it.

## 2. Run the criteria no child recorded

Write your own retrospective first, once for the run, per
`references/retrospective.md` with the parent as its issue, and fold its
project-level items into the parent's friction log, so step 3 disposes of them
too.

Every `A#` met by a run, such as an eval or a live exercise, that no child's
own criteria record is yours to run now. Record each run's output as a section
of the PR description, under the `A#` it is for. Running a criterion is not
judging it: whether a run meets its `A#` is the reviewer's call, on this PR.

## 3. Dispose of the friction log

Every friction-log entry gets exactly one disposition: a follow-up issue, or
`Dropped, because <reason>`. Draft them all first, as a table, then show the
operator the table and the exact text of every follow-up before filing any. An
entry about a `dnbg-*` plugin's own tooling is filed upstream under the
always-on "When shipped tooling doesn't fit, tell the user" rule, and that rule
needs the operator's approval of the exact text. File the approved follow-ups
per `issue-workflow`'s `references/creating.md`. Without `AskUserQuestion`, the
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

## 4. Write the as-built design and open the PR

`<doc path>` is `docs/design/<name>.md`, where `<name>` is the parent's title
as a lowercase-dashed slug. If the repo already keeps designs somewhere else
under `docs/`, use that location instead. Open the PR as a draft per
`git-workflow`, self-review included. Its description opens with
`Closes <parent URL>`, so the merge closes the parent, and carries step 2's
runs and step 3's table.

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
  leads to, and its recorded run, by URL. Say nothing about whether they meet
  it.
- **Replace the candidate decomposition with a "Where it was built" table**: each
  child's title, its `Covers`, and its merged PR URLs.
- **Drop execution state**: the decision log's states, `Depends on`, claims,
  the friction log, and Required reading.

## 5. Send it to review, and see it through

Send it to review per `git-workflow`'s "After opening a draft PR". When it is
out of draft, dispatch `reviewer` on the parent, in the background:

> Act as the reviewer on `<parent URL>`, in `reviewer`'s issue mode. It is a
> tracking issue, so grade the whole project on its closeout PR. You were
> dispatched by an orchestrator, so follow `issue-workflow`'s
> `references/delegated.md` wherever a skill asks the operator something.

Its review arrives on the PR, so handle every round as an author does, per
`git-workflow`'s `references/review-rounds.md`. A finding on an `A#` with no
recorded run is answered by running it and recording it in the description, as
in step 2. A finding this PR cannot answer, such as unbuilt work that a new
child would own, is an escalation, as `references/multi-issue.md`'s "Triage and
the log" describes: what to build next is the operator's call. When the review
is clean, give the operator the merge handoff per `git-workflow`'s
`references/merge.md`. Never merge.

The merge closes the parent. Run `git-workflow`'s post-merge cleanup, then go to
`references/multi-issue.md`'s "Stop". If the PR closes unmerged, ask the
operator whether to open a new one or stop.
