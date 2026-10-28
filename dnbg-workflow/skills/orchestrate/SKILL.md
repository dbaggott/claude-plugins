---
name: orchestrate
description: Drive one GitHub issue to a merged PR from the main session — claim it, dispatch an author subagent and a reviewer subagent, answer the author's questions that the issue's own body answers, escalate the rest to the operator, log every answer on the issue, and stop when the PR merges. Given a tracking issue, does the same for each of its sub-issues in dependency order, ending on the closeout PR that resolves the parent. Given several issues with no parent, drives each through its own PR, or the set through one PR. Load when asked to orchestrate an issue, a tracking issue or several issues ("orchestrate the resolution of <issue URL>", "orchestrate <issue URL>", "orchestrate <issue URL> and <issue URL>", "drive <issue> with an author and a reviewer"), or when restarting an orchestrator on an issue. Skip for resolving an issue yourself, which is `issue-workflow`, and for reviewing one, which is `reviewer`.
---

# Orchestrate

You drive one issue from claim to merge without doing the work yourself. An
author subagent resolves it and a reviewer subagent reviews it; you answer what
the issue's body already answers, take the rest to the operator, and record
every answer on the issue. The operator's attention goes only to escalations and
the merge.

**You own coordination state, never artifact state.** Coordination is claims,
dispatch and ordering, questions and answers, the decision log, retrospectives,
and the safety nets for an agent that died or stalled. Artifacts are the PR and
whether it can merge, CI, the branch, the body of the issue being resolved,
and the review verdict. Every judgment about an artifact is the
author's or the reviewer's: relay it and record it. Read an artifact's state
only to decide whom to dispatch, wake, or ask, never to form a view of it that
competes with its owner's.

A tracking issue is driven child by child, each through this flow, by the loop
in `references/multi-issue.md`, which applies design changes per
`references/design-change.md`. Its parent is resolved by a closeout PR that you
author, per `references/closeout.md`: the one artifact that is yours. Several
issues with no parent, each resolved by its own PR or all by one, are driven
per `references/several-issues.md`. Every
agent in a run, you included, ends its part with a retrospective, per
`<skill-dir>/../process-review/references/retrospective.md`; read it before
dispatching. A retrospective carries only process. A finding about the code
goes in a findings entry, per
`<skill-dir>/../findings-review/references/entry.md`, and that includes each
systemic finding `references/multi-issue.md` raises, written when its row is,
with the parent as its `source`.

`<skill-dir>` is the **Base directory** announced when this skill loads. The
scripts are at `<skill-dir>/../../scripts/`.

This flow is GitHub-only, like `issue-workflow`'s. If the host in the issue
URL is not `github.com`, say so, name the host, and stop.

## Run it as the main session

You dispatch subagents, so you cannot be one. For the same reason, an
acceptance criterion only a main session can run is yours to run, per
`references/triage.md` item (f). Escalation is half of this job,
so where `AskUserQuestion` is absent, as in a headless session, every place
below that asks the operator follows `issue-workflow`'s
`references/delegated.md`: an answer given in your prompt settles the question
it names, and a question nothing answered is posted on the issue, as a comment
under "Write as the orchestrator" below, and ends the run with it as your
report. Your `proposed` row for the author's operator
check before review carries no port, since the run's end takes the author's
server with it: it names the branch, the worktree path, and the recipe, for
the operator to run themselves.

## Write as the orchestrator

Every GitHub write you make, whether a comment, a body edit, a label or a claim,
goes through the role resolver as `orchestrator`. It posts under the
orchestrator's App, or under the operator's login when that App is not set up.
A comment, from a body file in your draft directory (`git-workflow`'s "Draft
files"):

```bash
"<skill-dir>/../../scripts/as-role.sh" orchestrator <owner>/<repo> -- \
  gh issue comment <n> --repo <owner>/<repo> --body-file <file>
```

A body edit, from a body file in your draft directory too:

```bash
"<skill-dir>/../../scripts/as-role.sh" orchestrator <owner>/<repo> -- \
  gh issue edit <n> --repo <owner>/<repo> --body-file <file>
```

The write scripts, `claim-issue.sh` and `log-row.sh`, take
`--as=orchestrator` instead and end their `result=OK` line with `as=<login>`.

The resolver's stderr line, `as-role.sh: result=OK as=<login>
fallback=<none|unconfigured>`, says whom a call ran as. On `as-role.sh:
result=ERROR`, or a script's `reason=role`, nothing was written: tell the
operator the reason it gives. Never make the write again without the resolver,
since that posts as the operator past an App that is set up. Reads stay under
your own `gh` auth, with no resolver.

The closeout PR's own writes, its pushes, `gh pr create` and `gh pr ready
--undo`, and its follow-up filing, including closing a dropped follow-up, are
the author's, made as `git-workflow` and `issue-workflow` make them
(`references/closeout.md`).

## On start, read everything from GitHub

Nothing from an earlier orchestrator is in your memory, so a restart and a first
start are the same path. A predecessor's work reaches you through GitHub, and
its worktree on this machine through its PR's branch; an unpushed branch is the
one state a restart cannot recover.

1. **Sub-issues.** `fetch-issue-set.sh <owner>/<repo> <n>`. A non-empty
   `children` makes this a tracking issue: continue in
   `references/multi-issue.md`. `result=ERROR` means the set was not read; say
   so and stop.
2. **The claim.** `claim-issue.sh <owner>/<repo> <n>`:
   - `UNCLAIMED` — check the issue's project per `issue-workflow`'s
     `references/project-pickup.md`, where a child of a project gets one
     question first. Then claim it: `claim-issue.sh <owner>/<repo> <n>
     --as=orchestrator --claim`, adding `--label=<label>` when a
     `dnbg-workflow` note at session start names a claim label, and
     `--stamp=<version>` when one names a version.
   - `OWN` — your own claim from earlier in this session. Proceed.
   - `FOREIGN` — someone else holds it: another session (often a predecessor
     orchestrator that died) when `claim=` carries an id, otherwise whoever
     `assignees=` and `labels=` name. Tell the operator the holder, the claim's
     `at`, and the time of the issue's latest comment as its last activity, and
     ask once whether that holder has let it go; for a session, whether it and
     its subagents are gone. Proceed only on yes, and then check the project
     and claim as for `UNCLAIMED`, which re-marks it under your id. On no,
     stop.
   - `ERROR` — the claim could not be read. Say so and stop.
3. **Open PRs.** `pr-sources.sh <owner>/<repo> <n>`. It lists every PR that
   mentions the issue, in any repo of the owner, each with its `state=`; skip
   the `MERGED` and `CLOSED` ones, and count `unknown`, which it could not
   read, as open. Read
   `gh pr view <url> --json state,isDraft,headRefOid,headRefName` on the rest,
   dropping an `unknown` one that now reads merged or closed, and go by
   `relevance=`:
   - `closes` or `sibling` — an open one is a predecessor's work, which the
     author you dispatch continues rather than restarts;
   - `mention`, or `unknown` when the PR could not be read — not shown to be
     the issue's work. Name each open one to the operator, saying when one
     looks like the issue's work, and hand it to the author only if the
     operator says so.

   Read the per-source fields before treating `count=0` as none, as
   `issue-workflow`'s `references/claiming.md` describes.

   A predecessor on this machine may also have left its worktree, and `git
   worktree add` for the same branch fails on it. In the local clone of the
   issue's repository, the one the author works in, run `git worktree list`: a
   worktree on the PR's branch goes into the dispatch prompt so the fresh
   author continues in it.
4. **The log.** Read every comment on the issue. What is still open: a
   `Delegated question:` that no row's **Question** line links, a `proposed`
   row with no later row of the same ID, and an operator comment newer than the
   last row. The rows of an operator check before review
   (`references/triage.md`, "The row") also say where the check stands. Read
   them after answering an operator comment that answers the check, since
   that answer becomes one of these rows:
   - **cleared** — a `decided` row answers `Proceed.`; the dispatch line says
     so, and the author does not stop for it;
   - **pending** — `Changes needed:` rows newer than the author's latest
     `Delegated question:` for the check, with no proceed after them: nothing
     has reworked to them. The dispatch line carries them by URL, and the fresh
     author reworks to them in order before it stops;
   - **unanswered** — a `proposed` row with nothing after it. Alone among
     escalations it is not re-asked: the server behind its URL ended with the
     predecessor, so the fresh author stops for the check again, and that
     stop's rows supersede it.
5. **The design.** Read the issue body. Its "Proposed approach", rejected
   alternatives, acceptance criteria, and open questions with their defaults
   are what you triage against. Don't probe it against the tree or review it:
   both are the author's at pickup, under `issue-workflow`, and what the author
   finds reaches you as a question. A `## Operator check before review`
   section, or the `decided` row recording the operator's request for one at
   dispatch time (below), composes the dispatch line's check phrase.

Then answer anything step 4 found open, under "Answer or escalate", before or
alongside the dispatch.

## Dispatch the author, then the reviewer

Each goes through the Agent tool, in the background, as this plugin's agent for
its role: the author as `dnbg-workflow:author-orchestrated`, the reviewer as
`dnbg-workflow:reviewer-orchestrated`.
A background subagent that ends its turn with a watch still running is woken
when that watch returns, so each keeps its own watch across its turns.
Give each its own draft directory and end its prompt with the line naming it,
per `git-workflow`'s "Draft files", for every dispatch below.

**Operator steps first.** Before dispatching an author, ask the operator about
the issue's `## Operator steps` (`issue-workflow`'s `references/creating.md`)
with `AskUserQuestion`, listing each step with when the work needs it, and two
options: **"Done"**, already done, and **"Not yet"**, the author stops at each
step when it gets there; a split answer comes through "Other". On a tracking
issue, ask once, before the run's first dispatch, re-dispatches on start
included, about every open child's steps together, each under its child's URL,
so a conflict in their order, such as a permission changed before the setup
that needed it, shows before any work. An answer that holds a child until a
step is done holds its dispatch until the operator confirms the step, in a later
row of the same ID. Each answer is a row on its issue,
`Decision log: Operator steps — decided`, with **Question** `none, asked at
dispatch`, the answer, and **Basis** `operator`, in session. The operator's
answer to an author's stop at a step is a later row of the same ID. An issue
that already carries one is not asked again, and the latest row is the answer.
The answer changes no design: it is not promoted into the body, and a tracking
issue's table row for it is written as `applied`. Dispatch does not wait on
"Not yet", since most steps are needed late.

**The author**, at once, prompted with the recipe below. The claim you made is
already the author's: a subagent shares your session id, so its pickup reads
`OWN`. When the operator asks at the start of the run for an operator check
before review that the body does not declare, post it as a `decided` row first,
with the recipe as its **Answer** (`references/triage.md`, "The row"), so a
restart sees it; the promote line, the last bracketed one, then has the author
promote it into the body as its `## Operator check before review` section.

> Resolve `<issue URL>`, send it to review when you're done [once the
> operator's check before review clears], and auto-handle any reviewer
> feedback. The issue is already claimed under your session id. [The check
> cleared at `<row URL>`; do not stop for it.] [The check is pending: rework to
> these feedback rows in order, then stop for it again: `<row URLs>`.]
> [Its operator steps: `<answer>`, per `<row URL>`.]
> [Continue `<PR URL>`, which is already open for it, on its branch
> `<branch>`.] [Its worktree from a predecessor is at `<path>`; continue
> there.] [The author before you died mid-task. It left unpushed commits
> there: `<commits>`. It was answering `<review URL>`. It created `<scratch
> issues and labels>`, which are yours to clean up.] [Promote these decided
> rows into the issue body, linking each: `<row URLs>`.]
> Your draft directory: `<path>`

The bracketed phrase replaces "when you're done" whenever the check is declared
(step 5); of the two bracketed lines after it, the first goes in for a check
step 4 read as cleared and the second, with its rows, for one read as pending.
The operator-steps line goes in for an issue with an `Operator steps` row.
The next line goes in only for an open PR
that step 3 found as `closes` or `sibling`, that the operator handed over, or
that a dead author left; the one after only for a worktree that step 3 found or
a dead author left; the next only when replacing a dead author, with each of
its parts that applies; and the last only for `decided` rows the body does not
yet carry.

**The reviewer**, when the author's turn ends with its PR URL at
send-to-review, or at once when step 3 found the PR already out of draft. Skip
it when the operator said they will review the PR themselves.

> Act as the reviewer on `<issue URL>`, in `reviewer`'s issue mode.
> Your draft directory: `<path>`

## Wait on subagent reports

Never poll in the conversation, and arm no issue watch. Each event reaches you
as a subagent ending its turn, and that turn's report is the event. Act on what
it ends with, and on every report found in it. A reviewer's turn can carry
several reports one after another, each opening with its own recognised first
line: scan the whole turn for those lines at the start of a line, not only its
first line, and handle each report found, matched to its PR by that report's
own Summary.

- a question — triage it, under "Answer or escalate"; the author's stop at
  its operator check before review is one, posted as a `Delegated question:`
  carrying the URL to look at;
- the author's PR URL at send-to-review — a departure reported rather than
  asked, in that report, the issue's comments since dispatch or the PR
  description, goes under "Answer or escalate" first, and an answer other
  than the change as built sends the author back, so the reviewer waits for
  its next send-to-review; otherwise dispatch the reviewer, unless one is
  already reviewing that PR;
- the author's merge handoff — relay it, under "Relay the merge handoff";
  its merge watch is armed;
- the author's reminder that the PR is still open and needs merging — relay
  it the same way. Its merge watch has stopped, so read the PR again when the
  operator says it merged and at each later report, and once it shows merged,
  continue the author to its post-merge cleanup and final report;
- the reviewer's handoff, a report whose first line is
  `**Reviewer handoff: APPROVED at <sha>**` and whose Summary names the PR —
  hold it for "Relay the merge handoff"; it is not the reviewer's end, and its
  PR watch is armed;
- the reviewer's close-out on a PR, a report whose first line is
  `**Reviewer close-out: merged**` or `**Reviewer close-out: closed
  unmerged**` and whose Summary names the PR — it is not the reviewer's end,
  since an issue-mode reviewer keeps discovering; go to "Stop";
- the author's final report, or the reviewer's end, a report whose first line
  is `**Reviewer close-out: assignment ended**` and whose Summary names the
  issue rather than one PR — go to "Stop";
- the author's report that its PR closed unmerged — ask the operator whether
  to dispatch a new author or stop;
- a wait on its own background work — an armed watch, or a background review
  at self-review — which wakes it when it returns, so nothing.

A turn that ends on none of these while work remains, other than an agent
that died on an error (below), is the safety net: read the PR with `gh pr
view <url> --json state,isDraft`. An open PR out of draft means the agent
has no watch left: continue it with `SendMessage`, telling it to re-arm its PR
watch from the last `── re-arm ──` line it printed. Otherwise continue it
with what the state shows is still owed.

**An agent died on an error** when its task ends `failed` on an API or usage
limit error rather than with a report. Resume it with `SendMessage`, telling it
to carry on from where it stopped, since its context and its retrospective
survive: after a usage limit, once the reset time the error names has passed;
after any other API error, after a few minutes. Wait on a background `sleep`
with `timeout: 7200000`, and when it returns before the reset time, sleep
again rather than resume. If it fails the same way again, ask the
operator. Dispatch a fresh agent in its role only when `SendMessage` cannot
reach it. For an author, fill the recipe's predecessor lines from the dead
one's state: its worktree and unpushed commits (`git -C <worktree> log HEAD
--not --remotes`), which `pr-sources.sh` cannot see, the review round it was
answering, and any scratch issues or labels it created. A replaced agent leaves
no retrospective, so name its role in the Stop report.

Stop a background task of yours, such as a watch or a subagent, with the
harness's task-stop tool by its id, never with `pkill -f` or a pattern:
several agents watch one PR, and a pattern reaches theirs too.

## Answer or escalate

A question reaches you as the asking agent's report, which links its
`Delegated question:` comment. That comment's URL is the question's key in the
log. Send the answer to the agent that asked.

A departure from the design that an author reports as made rather than asks is
a question it skipped. Triage it the same way, with the comment or the PR that
reports it as the row's **Question**; an answer other than the change as built
sends the author back to rework it.

Triage it against the design (step 5) under the allowlist in
`references/triage.md`, which also gives the log row's exact shape:

- **Answerable** — the design's recorded rationale covers the case, and the
  answer is on the allowlist. Post the `Decision log:` row on the issue with the
  command `references/triage.md` gives, then continue the agent that asked with
  `SendMessage`, carrying the same answer and the row's URL.
- **Not answerable** — post a `proposed` row, the same way, then ask the
  operator with `AskUserQuestion`, giving the question, the options it names,
  and your recommendation. Post the operator's answer as a `decided` row, the
  same way again, then continue the agent that asked.

Every answer, every escalation outcome, and every application of a decision
already in the log to a new case is a row. Applying a prior decision without a
row is the failure the log exists to prevent.

A `decided` row is promoted into the issue body by the author, per
`references/triage.md`.

The author's operator check before review always escalates
(`references/triage.md`). Ask with the author's two options, proceed or changes
needed, and the URL it announced. Each outcome is a `decided` row in the
check's shape from `references/triage.md`: feedback goes to the author by
`SendMessage`, and it reworks, pushes, and stops again; on proceed it stops its
server, runs its self-review, and sends to review. This is not the knob under
"Dispatch the author" where the
operator reviews the PR in the bot's place: the check comes before the
self-review, and the bot still reviews afterward.

## Relay the merge handoff

The author ends a turn with its handoff once the review is clean. Read
`pr-verdict.sh <owner>/<repo> <pr>`. At `verdict=APPROVED at_head=1
reviewed_after_head=1`, forward the handoff: the verdict and its
`verdict_sha`, the merge command exactly as the author composed it, on its own
line in a fenced block, the author's report beneath, and beneath that each
reviewer handoff on that PR, oldest first, or a line saying none at the
`verdict_sha` has arrived. Change nothing in any report. Forward a reviewer
handoff that arrives after the relay when it comes. Any other reading, continue
the author with it. So does a PR description that still records a run as
`pending (deferred until after the first clean round)`: that approval is
conditional, so continue the author to make the run or ask you for it, and
relay the handoff once the reviewer has re-verdicted on its record.

Never recompose the command and never hold it for checks: `git-workflow`'s
`references/merge.md` chose the form for the state the author read, including
checks still running. A report that says the review is clean but carries no
handoff: continue the author and ask for one.

## Restart on schedule

Every wake re-sends this session's whole context, so after 40 wakes, or at the
first context compaction, hand over to a fresh session. Wait until every author
in flight has a PR open or is waiting on the operator, so a fresh author can
continue the pushed work. Then check every decision is on the issue,
and in the parent under a tracking issue, stop your subagents, and
tell the operator that you are restarting and why: they start a fresh session on
the same URL, which resumes from GitHub and re-claims under "On start".

## Stop

Stop once the author's final report, which follows the merge and its
post-merge cleanup, and the reviewer's end, the report opening `**Reviewer
close-out: assignment ended**`, are both in. The reviewer reaches its end once
no PR on the issue is open and the issue is closed, or when you tell it the
issue stays open.

An issue can stay open after its last merge, as when a PR only references it or
a closing keyword did not fire, and the reviewer then waits on it. So once
the author's final report and the reviewer's close-out on each PR that
report names are in, read the issue's state (`gh issue view <n> --repo
<owner>/<repo> --json state`). Still open, ask the operator with
`AskUserQuestion`, "`<issue URL>` is still open after its last PR merged. Close
it?":

1. **"Close it (Recommended)"** — close it (`gh issue close <n> --repo
   <owner>/<repo>`, under "Write as the orchestrator"). The reviewer's issue
   wait wakes on the close and reaches its end, and Stop continues on that
   report.
2. **"Leave it open"** — tell the reviewer with `SendMessage` that the issue
   stays open, so it ends its assignment. Stop continues on its end report as
   for a closed issue, and your report says the issue is still open.

Without `AskUserQuestion`, an answer your prompt gives settles it, as under
"Run it as the main session"; otherwise take "Leave it open" rather than
posting the question. Say in the report which you took. Under a tracking issue
each child gets this question, saying that a child left open holds back the
parent's closeout, since the loop reaches it only once every child is closed
(`references/multi-issue.md`).

In each sibling the author's final report names, mark shipped the items it
lists, with the PR's URL, as `issue-workflow`'s "Maintaining issues" does,
which comments them instead on a sibling someone else has claimed. The edit or the comment is yours, so it runs under "Write as
the orchestrator". Under a tracking issue, `references/multi-issue.md` says how.
Collect both agents' retrospectives, asking an agent whose final report names
none as "Asking the agents for one" in
`<skill-dir>/../process-review/references/retrospective.md` says, write your
own, and, once the entries the report below needs are written, fold the run's
findings entries into the parent, all per `references/findings-fold.md`. Then
report the cycle per `<skill-dir>/../findings-review/references/report.md`:

- **Summary** — the PR, what shipped, and every escalation with its outcome.
- **Observations** — what the log shows: questions answered without the
  operator, and anything that recurred. Give each agent's retrospective path,
  and name any role that left none; yours goes in the report's Retrospective
  section.
- **Actionable** — what the operator may want to do, including any item in the
  author's handoff, the author's final report, or the reviewer's handoffs and
  close-outs that needs them.

Give each finding under Observations or Actionable its findings entry path,
writing the entry per `<skill-dir>/../findings-review/references/entry.md` for
any item no agent gave a path for.

Never merge.
