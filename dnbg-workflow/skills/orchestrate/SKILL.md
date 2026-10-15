---
name: orchestrate
description: Drive one GitHub issue to a merged PR from the main session — claim it, dispatch an author subagent and a reviewer subagent, answer the author's questions that the issue's own body answers, escalate the rest to the operator, log every answer on the issue, and stop when the PR merges. Given a tracking issue, does the same for each of its sub-issues in dependency order, ending on the closeout PR that resolves the parent. Load when asked to orchestrate an issue or a tracking issue ("orchestrate the resolution of <issue URL>", "orchestrate <issue URL>", "drive <issue> with an author and a reviewer"), or when restarting an orchestrator on an issue. Skip for resolving an issue yourself, which is `issue-workflow`, and for reviewing one, which is `reviewer`.
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
author, per `references/closeout.md`: the one artifact that is yours. Every agent in a run, you included,
ends its part with a retrospective, per `references/retrospective.md`; read it
before dispatching.

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
it names, and a question nothing answered is posted on the issue and ends the
run with it as your report.

## On start, read everything from GitHub

Nothing from an earlier orchestrator is in your memory, so a restart and a first
start are the same path.

1. **Sub-issues.** `fetch-issue-set.sh <owner>/<repo> <n>`. A non-empty
   `children` makes this a tracking issue: continue in
   `references/multi-issue.md`. `result=ERROR` means the set was not read; say
   so and stop.
2. **The claim.** `claim-issue.sh <owner>/<repo> <n>`:
   - `UNCLAIMED` — claim it: `claim-issue.sh <owner>/<repo> <n> --claim`,
     adding `--label=<label>` when a `dnbg-workflow` note at session start names
     a claim label, and `--stamp=<version>` when one names a version.
   - `OWN` — your own claim from earlier in this session. Proceed.
   - `FOREIGN` — someone else holds it: another session (often a predecessor
     orchestrator that died) when `claim=` carries an id, otherwise whoever
     `assignees=` and `labels=` name. Tell the operator the holder, the claim's
     `at`, and the time of the issue's latest comment as its last activity, and
     ask once whether that holder has let it go; for a session, whether it and
     its subagents are gone. Proceed only on yes, and then claim with
     `--claim`, which re-marks it under your id. On no, stop.
   - `ERROR` — the claim could not be read. Say so and stop.
3. **Open PRs.** `pr-sources.sh <owner>/<repo> <n>`, then
   `gh pr view <url> --json state,isDraft,headRefOid` on each. It lists every
   PR that mentions the issue, in any repo of the owner, so go by `relevance=`:
   - `closes` or `sibling` — an open one is a predecessor's work, which the
     author you dispatch continues rather than restarts;
   - `mention`, or `unknown` when the PR could not be read — not shown to be
     the issue's work. Name each open one to the operator, saying when one
     looks like the issue's work, and hand it to the author only if the
     operator says so.

   Read the per-source fields before treating `count=0` as none, as
   `issue-workflow`'s `references/claiming.md` describes.
4. **The log.** Read every comment on the issue. What is still open: a
   `Delegated question:` that no row's **Question** line links, a `proposed`
   row with no later row of the same ID, and an operator comment newer than the
   last row.
5. **The design.** Read the issue body. Its "Proposed approach", rejected
   alternatives, acceptance criteria, and open questions with their defaults
   are what you triage against. Don't probe it against the tree or review it:
   both are the author's at pickup, under `issue-workflow`, and what the author
   finds reaches you as a question.

Then answer anything step 4 found open, under "Answer or escalate", before or
alongside the dispatch.

## Dispatch the author, then the reviewer

Each goes through the Agent tool, in the background, as this plugin's agent for
its role: the author as `dnbg-workflow:orchestrated-author`, the reviewer as
`dnbg-workflow:orchestrated-reviewer`.
A background subagent that ends its turn with a watch still running is woken
when that watch returns, so each keeps its own watch across its turns.
Each also shares your scratchpad directory, so a draft file at a chosen name
there is one you and it can both write; every draft file comes from `mktemp`, per `git-workflow`'s "Writing the
PR description".

**The author**, at once, prompted with the recipe below. The claim you made is
already the author's: a subagent shares your session id, so its pickup reads
`OWN`.

> Resolve `<issue URL>`, send it to review when you're done, and auto-handle any
> reviewer feedback; never merge. You were dispatched by an orchestrator, so
> follow `issue-workflow`'s `references/delegated.md` wherever a skill asks
> the operator something. The issue is already claimed under your session id.
> [Continue `<PR URL>`, which is already open for it.] [Promote these decided
> rows into the issue body, linking each: `<row URLs>`.] When you send the PR to
> review, end your turn with its URL. When the review is clean, re-arm your
> merge watch and end your turn with your merge handoff. If the PR closes
> unmerged, end your turn saying so. When it merges, finish
> the post-merge cleanup, write a retrospective per
> `<skill-dir>/references/retrospective.md`, and report under Summary,
> Observations, Actionable, and Retrospective, the last giving the file's path.

The first bracketed line goes in only when step 3 found an open `closes` or
`sibling` PR, or the operator handed one over, the second
only for `decided` rows the body does not yet carry. In both recipes,
`<skill-dir>` is written out as the absolute path, since the agent has not
loaded this skill.

**The reviewer**, when the author's turn ends with its PR URL at
send-to-review, or at once when step 3 found the PR already out of draft. Skip
it when the operator said they will review the PR themselves.

> Act as the reviewer on `<issue URL>`, in `reviewer`'s issue mode. You were
> dispatched by an orchestrator, so follow `issue-workflow`'s
> `references/delegated.md` wherever a skill asks the operator something. When
> your review ends, write a retrospective per
> `<skill-dir>/references/retrospective.md`, and end your final report with a
> **Retrospective** section giving the file's path.

## Wait on subagent reports

Never poll in the conversation, and arm no issue watch. Each event reaches you as a subagent ending its turn, and that turn's report is the event.
Act on what it ends with:

- a question — triage it, under "Answer or escalate";
- the author's PR URL at send-to-review — dispatch the reviewer, unless one
  is already reviewing that PR;
- the author's merge handoff — relay it, under "Relay the merge handoff";
  its merge watch is armed;
- the author's reminder that the PR is still open and needs merging — relay
  it the same way. Its merge watch has stopped, so read the PR again when the
  operator says it merged and at each later report, and once it shows merged,
  continue the author to its post-merge cleanup and final report;
- the author's final report, or the reviewer's end — go to "Stop" once both
  are in;
- the author's report that its PR closed unmerged — ask the operator whether
  to dispatch a new author or stop;
- a wait on its own background work — an armed watch, or a background review
  at self-review — which wakes it when it returns, so nothing.

A turn that ends on none of these while work remains is the safety net:
read the PR with `gh pr view <url> --json state,isDraft`. An open PR out of
draft means the agent has no watch left: continue it with `SendMessage`,
telling it to re-arm its PR watch from the last `── re-arm ──` line it
printed. Otherwise continue it with what the state shows is still owed.

## Answer or escalate

A question reaches you as the asking agent's report, which links its
`Delegated question:` comment. That comment's URL is the question's key in the
log. Send the answer to the agent that asked.

Triage it against the design (step 5) under the allowlist in
`references/triage.md`, which also gives the log row's exact shape:

- **Answerable** — the design's recorded rationale covers the case, and the
  answer is on the allowlist. Post the `Decision log:` row on the issue, then
  continue the agent that asked with `SendMessage`, carrying the same answer and
  the row's URL.
- **Not answerable** — post a `proposed` row, then ask the operator with
  `AskUserQuestion`, giving the question, the options it names, and your
  recommendation. Post the operator's answer as a `decided` row, then continue
  the agent that asked the same way.

Every answer, every escalation outcome, and every application of a decision
already in the log to a new case is a row. Applying a prior decision without a
row is the failure the log exists to prevent.

A `decided` row is promoted into the issue body by the author, per
`references/triage.md`.

## Relay the merge handoff

The author ends a turn with its handoff once the review is clean. Read
`pr-verdict.sh <owner>/<repo> <pr>`. At `verdict=APPROVED at_head=1
reviewed_after_head=1`, forward the handoff as it stands: the merge command
exactly as the author composed it, on its own line in a fenced block, and the
author's report beneath, adding only the verdict and its `verdict_sha`. Any
other reading, continue the author with it.

Never recompose the command and never hold it for checks: `git-workflow`'s
`references/merge.md` chose the form for the state the author read, including
checks still running. A report that says the review is clean but carries no
handoff: continue the author and ask for one.

## Restart on schedule

Every wake re-sends this session's whole context, so after 40 wakes, or at the
first context compaction, hand over to a fresh session. Wait until every author
in flight has its PR out of draft or is waiting on the operator, so a fresh
author can continue the pushed work. Then check every decision is on the issue,
and in the parent under a tracking issue, stop your subagents, and
tell the operator that you are restarting and why: they start a fresh session on
the same URL, which resumes from GitHub and re-claims under "On start".

## Stop

Stop once the author's final report, which follows the merge and its
post-merge cleanup, and the reviewer's end are both in. If the issue is still
open then, say so in the report. Collect both agents'
retrospectives, write your own, and fold the project-level items into the
parent, all per `references/retrospective.md`. Then report the cycle under
three headings:

- **Summary** — the PR, what shipped, and every escalation with its outcome.
- **Observations** — what the log shows: questions answered without the
  operator, and anything that recurred. Give each retrospective's path, and name
  any role that left none.
- **Actionable** — what the operator may want to do, including any author or
  reviewer report item that needs them.

Never merge.
