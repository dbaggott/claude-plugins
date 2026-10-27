# Orchestrate: resolving a tracking issue through its closeout PR

Part of the `orchestrate` skill. Read this when `references/multi-issue.md`'s
loop finds every child closed. The parent resolves the way a plain issue does:
one PR closes it, `reviewer`'s issue mode on the parent reviews that PR, and the
operator merges it. You are that PR's author. Step 5 needs the operator's
approval, so this runs in the main session.

The closeout PR writes the project's as-built design into the repo and settles
its findings log. The parent's shape and IDs are in `issue-workflow`'s
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
`issue-workflow`'s `references/claiming.md` describes. An open PR whose
`closingIssuesReferences` include the parent is a predecessor's closeout PR.
Continue it rather than opening a second, at the first of steps 4 to 6 its
description does not carry; one out of draft resumes at step 6, with a reviewer
dispatched as step 6 does if none is reviewing it. Run step 2 too while its
description has no step-5 table.

## 2. Gather the findings into the log

Bring every finding of the project into the parent's **Findings log**, each as
one bullet in the form `references/retrospective.md`'s "Fold the project's
findings into the parent" gives, added with one
`log-row.sh --bullet="Findings log" --as=orchestrator` call. The call adds only
the bullets the log does not already carry. The bullets come from two places:

- **The comments relayed by a child's orchestrator** that was not the parent's
  writer: those on the parent whose first line reads
  `Findings log items from <child URL>` (`issue-workflow`'s
  `references/tracking-issue.md`, "Who writes the body"), about a child in the
  set and posted by your own login, the author's or the orchestrator's: the
  `login=` of `"<skill-dir>/../../scripts/as-role.sh" --login author <owner>/<repo>`
  or of `… --login orchestrator <owner>/<repo>`, in either spelling, `<login>`
  or `<login>[bot]`. Yours covers a child run whose role fell back. Pass each
  bullet as a `--text` without its leading `- `.
- **The findings store**: every entry under the findings root
  (`<skill-dir>/../findings-review/references/entry.md`, "Where it goes"),
  across every repo's directory, whose `project:` is the parent's URL and whose
  `disposition` is `open`, which takes in entries no run folded. Skip an entry
  whose path a bullet already names.

## 3. Write the as-built design and open the PR

`<doc path>` is `docs/design/<name>.md`, where `<name>` is the parent's
description — its title without any `[<slug>] Tracking issue: ` prefix — as a
lowercase-dashed slug. If the repo already keeps designs somewhere else
under `docs/`, use that location instead. Open the PR as a draft per
`git-workflow`, self-review included, drafting its description in a file from
`mktemp` per that skill's "Writing the PR description". The description opens with
`Closes <parent URL>`, so the merge closes the parent.

The doc is the parent body as built, not as planned:

- **Open with one line** linking the tracking issue.
- **Keep** Problem, Goals, Non-goals, Constraints, Requirements, Decisions, Open
  questions, and End-to-end acceptance criteria, with **every ID unchanged**,
  including retired entries and their markings. Children, PRs and commits cite
  these IDs, and once the issue closes the doc is the only place they still
  resolve.
- **Fold the decision log into the entries it changed**, after collecting the
  children's comments whose first line starts with `Decision log: `, per
  `references/multi-issue.md`, "Collect the children's rows". Each entry reads in
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
  the findings log, and Required reading.

## 4. Run the criteria no child recorded

Every `A#` met by a run, such as an eval or a live exercise, that no child's
own criteria record is yours to run now. Record each run's output and the
commit it ran on as a section of the PR description, under the `A#` it is for,
with the per-file statements `issue-workflow`'s `references/resolving.md` asks
for when a later commit changes a file under the run's invalidating paths,
and link it from the doc's `A#`. Running a criterion is not judging it: whether
a run meets its `A#` is the reviewer's call, on this PR.

## 5. Dispose of the findings log

Every findings-log entry is reviewed with the operator and gets exactly one
disposition:

- **a follow-up issue** in the entry's `repo`;
- **`Dropped, because <reason>`**;
- **`Deferred`**, which leaves its findings entry `disposition: open` for
  `findings-review` to decide later, against a fresher tree.

An entry `findings-review` already decided (its `disposition` is no longer
`open`) keeps that decision: put it in the table as it stands, and ask nothing
about it. Propose one for each other entry the way `findings-review`'s steps 2
to 4 do: re-check the
entry against the default branch, merge entries that describe one problem, and
draft each follow-up's exact text, with **Deferred** where that skill would
propose **keep**. Draft them all first, as a table, then show the operator the
table and the exact text of every follow-up before filing any. Without
`AskUserQuestion`, the table and the follow-up texts are the question in
`<skill-dir>/../issue-workflow/references/delegated.md`, posted on the parent
as the orchestrator (`SKILL.md`, "Write as the orchestrator"); file nothing
until it is answered.

The table goes in the PR description, not the parent body. It is the findings
log's final state, and the merged PR is what the closed parent links to:

```markdown
| Entry | Disposition |
| --- | --- |
| 2026-10-13: export drops rows past the page size | <follow-up issue URL> |
| 2026-10-14: children diverged on date formatting | Dropped, because child 6 settled it |
| 2026-10-15: no test for the empty-archive path | Deferred |
```

Put the approved table in the description first, then file each approved
follow-up per `issue-workflow`'s `references/creating.md`, writing its URL into
its row as soon as it is filed. A row still without a URL on resume is searched
for by its title before it is filed. A follow-up that a review round turns into
a drop is closed as not planned, citing the round:
`"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- gh issue close <n> --repo <owner>/<repo> --reason "not planned" --comment "<round URL>"`.

Record each filed or dropped row in its entry, as `findings-review`'s step 5
does, when the entry is on this machine; a row whose entry is not stays in the
table alone.

Every write in this file is the author's, as `git-workflow`'s "Acting as the
author" describes, except the parent-body rows `log-row.sh` writes and the
disposition question posted on the parent, which are the orchestrator's.

## 6. Send it to review, and see it through

Send it to review per `git-workflow`'s "After opening a draft PR". When it is
out of draft, dispatch `reviewer` on the parent as
`dnbg-workflow:reviewer-orchestrated`, in the background:

> Act as the reviewer on `<parent URL>`, in `reviewer`'s issue mode. It is a
> tracking issue, so grade the whole project on its closeout PR.

Its review arrives on the PR, so handle every round as an author does, per
`git-workflow`'s `references/review-received.md` and
`references/review-findings.md`. A finding on an `A#` with no
recorded run is answered by running it and recording it, as in step 4.

A finding this PR cannot answer, such as unbuilt work that a new child would
own, is an escalation, as `references/multi-issue.md`'s "Triage and the log"
describes: what to build next is the operator's call. When the answer adds or
reopens a child, return the PR to draft with `"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- gh pr ready <pr> --repo <owner>/<repo> --undo` and go
back to the loop. It reaches this file again at `open=0`, where step 1 finds
the PR and you bring its doc up to date before sending it back to review.

When the review is clean, give the operator the merge handoff per
`git-workflow`'s `references/merge.md`, and re-arm the watch for the merge
from its `── re-arm ──` line per its `references/merge-wait.md`. Never merge. The merge closes the parent. Run
`git-workflow`'s post-merge cleanup (`references/post-merge.md`), then go to
`references/multi-issue.md`'s "Stop", once the reviewer's final report is in,
and write your own retrospective there, once for the whole run, with the parent
as its issue (`references/retrospective.md`, "Your own").
If the PR closes unmerged, ask the operator whether to open a new one or stop.
