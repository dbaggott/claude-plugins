---
name: orchestrate
description: Drive one GitHub issue to a merged PR from the main session — claim it, dispatch an author subagent and a reviewer subagent, answer the author's questions that the issue's own body answers, escalate the rest to the operator, log every answer on the issue, and stop when the PR merges. Also closes out a finished tracking issue. Load when asked to orchestrate an issue ("orchestrate the resolution of <issue URL>", "orchestrate <issue URL>", "drive <issue> with an author and a reviewer"), when restarting an orchestrator on an issue, or when asked to close out a tracking issue. Skip for resolving an issue yourself, which is `issue-workflow`, and for reviewing one, which is `reviewer`.
---

# Orchestrate

You drive one issue from claim to merge without doing the work yourself. An
author subagent resolves it and a reviewer subagent reviews it; you answer what
the issue's body already answers, take the rest to the operator, and record
every answer on the issue. The operator's attention goes only to escalations and
the merge.

Closing out a finished tracking issue is a separate entry, in
`references/closeout.md`. Every agent in a run, you included, ends its part with
a retrospective, per `references/retrospective.md`; read it before dispatching.

`<skill-dir>` is the **Base directory** announced when this skill loads. The
scripts are at `<skill-dir>/../../scripts/`.

This flow is GitHub-only, like `issue-workflow`'s. If the host in the issue
URL is not `github.com`, say so, name the host, and stop.

## Run it as the main session

You dispatch subagents, so you cannot be one. Escalation is half of this job,
so where `AskUserQuestion` is absent, as in a headless session, every place
below that asks the operator follows `issue-workflow`'s
`references/delegated.md`: an answer given in your prompt settles the question
it names, and a question nothing answered is posted on the issue and ends the
run with it as your report.

## On start, read everything from GitHub

Nothing from an earlier orchestrator is in your memory, so a restart and a first
start are the same path.

1. **Sub-issues.** `fetch-issue-set.sh <owner>/<repo> <n>`. A non-empty
   `children` makes this a tracking issue, which this mode does not run: say so
   and stop. `result=ERROR` means the set was not read; say so and stop.
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
   `gh pr view <url> --json state,isDraft,headRefOid` on each. An open PR is a
   predecessor's work, which the author you dispatch continues rather than
   restarts. Read the per-source fields before treating `count=0` as none, as
   `issue-workflow`'s `references/resolving.md` describes.
4. **The log.** Read every comment on the issue. What is still open: a
   `Delegated question:` that no row's **Question** line links, a `proposed`
   row with no later row of the same ID, and an operator comment newer than the
   last row.
5. **The design.** Read the issue body. Its "Proposed approach", rejected
   alternatives, acceptance criteria, and open questions with their defaults
   are what you triage against. Run `issue-workflow`'s critical review on it
   now: a body you believe is wrong is an escalation before any dispatch, not a
   problem to hand the author.

Then answer anything step 4 found open, under "Answer or escalate", before or
alongside the dispatch.

## Dispatch the author, then the reviewer

Each is a `general-purpose` subagent through the Agent tool, in the background.
A background subagent that ends its turn with a watch still running is woken
when that watch returns, so each keeps its own watch across its turns.

**The author**, at once, prompted with the recipe below. The claim you made is
already the author's: a subagent shares your session id, so its pickup reads
`OWN`.

> Resolve `<issue URL>`, send it to review when you're done, and auto-handle any
> reviewer feedback; never merge. You were dispatched by an orchestrator, so
> follow `issue-workflow`'s `references/delegated.md` wherever a skill asks
> the operator something. The issue is already claimed under your session id.
> [Continue `<PR URL>`, which is already open for it.] When you send the PR to
> review, end your turn with its URL. When it merges, finish the post-merge
> cleanup and report under Summary, Observations, and Actionable. When your
> part ends, write a retrospective per `<skill-dir>/references/retrospective.md`,
> and end your final report with a **Retrospective** section giving the file's
> path.

The bracketed line goes in only when step 3 found an open PR. In both recipes,
`<skill-dir>` is written out as the absolute path, since the agent has not
loaded this skill.

**The reviewer**, when the PR leaves draft (the PR watch's `READY`), or at once
when step 3 found the PR already out of draft. Skip it when the operator said
they will review the PR themselves.

> Act as the reviewer on `<issue URL>`, in `reviewer`'s issue mode. You were
> dispatched by an orchestrator, so follow `issue-workflow`'s
> `references/delegated.md` wherever a skill asks the operator something. When
> your part ends, write a retrospective per
> `<skill-dir>/references/retrospective.md`, and end your final report with a
> **Retrospective** section giving the file's path.

## Wait on three sources

Never poll in the conversation. Each event reaches you as one of these:

- **Subagent notifications.** The author's questions arrive as its turn-end
  report, and so do "sent to review" and its final report. A notification that
  says the agent is waiting on its own background work means its watch is
  armed. One that says it finished with no question in its report, while its PR
  is open and out of draft, means it has no watch left: continue it with
  `SendMessage`, telling it to re-arm its PR watch from the last `── re-arm ──`
  line it printed.
- **The issue watch**, armed once at start and re-armed from its own
  `── re-arm ──` line, always in the background:

  ```bash
  "<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <n> \
    --role=orchestrator --since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ```

  It wakes on comments, linked PRs, and the issue closing, never on a body edit
  or on what only your own bookkeeping writes: `Decision log:` rows, your own
  `Claimed by`, and the reviewer's assignment note. Everyone posts as one
  account, so its `comments=<login:url,…>` field names each remaining comment's
  author, and `overflowed=<n>` says the page did not reach back far enough, so
  read that issue's thread in full. Read each comment and classify it by its
  first line, then its author:

  | Comment | What it is | Action |
  | --- | --- | --- |
  | opens with `Delegated question:` | a question from whichever subagent's report links that comment's URL; both post under the operator's login | triage it, under "Answer or escalate" |
  | opens with `Claimed by` | another session claiming the issue mid-run | tell the operator and ask whether to stop |
  | anything else from the reviewer bot | a review round or verdict | none; the author handles rounds |
  | anything else under the operator's login | the operator, or the author's progress | read it; act only if it states a decision |

  An operator comment that states a decision is a decision: log it as
  `decided`, promote it into the body, and send it to any agent it affects. One
  that does not is noted and changes nothing.
- **The PR watch**, armed once a PR exists (the issue watch's `linked-pr`, or
  the author's report), in the background, with the same author role the author
  uses, so it sees the bot's reviews and the PR's state. Add `--was-draft` while
  the PR is a draft:

  ```bash
  WINDOW=21600 "<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <pr> \
    "<head>" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "" --role=author --last-verdict= \
    [--was-draft]
  ```

  `<head>` is the full SHA from `gh pr view <pr> --json headRefOid`. Re-arm
  from its `── re-arm ──` line, carrying `verdict_sha` into `--last-verdict`
  when a result names one. What a result asks of you:
  - `READY` — the PR left draft: dispatch the reviewer.
  - `ACTIVITY` — a review round. The author handles it; if its last
    notification said it finished, continue it as above. When
    `pr-verdict.sh <owner>/<repo> <pr>` reads `verdict=APPROVED at_head=1
    reviewed_after_head=1`, tell the operator the PR is ready to merge, with
    its URL.
  - `CLOSED state=MERGED` — go to "Stop". `CLOSED state=CLOSED` — tell the
    operator the PR was closed unmerged and ask whether to dispatch a new
    author or stop.
  - `DIRTY` — tell the operator. Re-spawn the watch once the author reports the
    conflict resolved.
  - `IDLE` — routine while a round is being worked; re-arm.
  - `ERROR` — the watch cannot see. Do not re-arm; check `gh auth status` and
    tell the operator.

The issue watch's `ERROR`, `IDLE`, and `CLOSED` follow the same rules: `ERROR`
is not a quiet issue, `IDLE` is re-armed, and `CLOSED` is the issue closing, so
check the PR's state and go to "Stop" if it merged.

## Answer or escalate

A question reaches you twice, as the asking agent's report and as its
`Delegated question:` comment. Handle it once, keyed by the comment's URL, and
send the answer to the agent that asked.

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

After each `decided` row, promote the decision into the issue body per
`issue-workflow`'s maintenance rule, so a cold reader of the body sees it
without reading the log.

## Stop

Stop when the PR has merged and the issue is closed. Wait for the author's final
report, since its post-merge cleanup is part of the run, and for the reviewer to
end. Collect both agents' retrospectives, write your own, and fold the
project-level items into the parent, all per `references/retrospective.md`. Then
report the cycle under three headings:

- **Summary** — the PR, what shipped, and every escalation with its outcome.
- **Observations** — what the log shows: questions answered without the
  operator, and anything that recurred. Give each retrospective's path, and name
  any role that left none.
- **Actionable** — what the operator may want to do, including any author or
  reviewer report item that needs them.

Never merge.
