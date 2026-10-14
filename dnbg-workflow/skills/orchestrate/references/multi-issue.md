# Orchestrate: a tracking issue's children

Part of the `orchestrate` skill. Read this when step 1 of `SKILL.md`'s "On
start" finds sub-issues. The parent's body is the design, in the shape
`issue-workflow`'s `references/tracking-issue.md` gives it, and each child is
driven by `SKILL.md`'s single-issue flow, changed only where this file says.

`<slug>` is the reviewer bot's login:
`jq -r .slug "${DNBG_REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/reviewer}/config.json"`.

## On start

1. **Claim the parent**, as `SKILL.md`'s step 2 claims an issue. A `FOREIGN`
   claim held by a session is the predecessor orchestrator, and the operator's
   answer about it covers every child it claimed.
2. **Take over the in-flight children**: the open ones carrying a claim, which
   are the ready set's `waiting` entries whose `reasons` include `claimed` (the
   loop's step 3, run now). Run `claim-issue.sh` on each. `OWN` is yours.
   `FOREIGN` with the predecessor's id is re-claimed with `--claim` once the
   operator has said the predecessor is gone. Any other holder is not part of
   this run: leave the child alone, and it waits like a blocker outside the
   project. For each child you hold, run `SKILL.md`'s steps 3 to 5 on it, then
   dispatch a fresh author, and a reviewer when its PR is out of draft.
3. **Read the parent's log**: its decision-log table, and the
   `Decision log: archived rows` comment if it has one. A `proposed` row is an
   escalation still waiting, and a `decided` row is work to finish before any
   dispatch (`references/design-change.md`). Read every comment on the parent
   newer than the last row for decisions the operator gave there.
4. **Review the design.** `SKILL.md`'s step 5, run on the parent's body.
5. **Arm the set watch** (below), then run the loop.

## The loop

Run it after start and after every event that can change the answer: a child
closing, a row reaching `applied`, a spec verdict on a child.

1. **Finish every `decided` row not yet `applied`**, per
   `references/design-change.md`.
2. **Scan for systemic problems** (below).
3. **Read the ready set:**

   ```bash
   "<skill-dir>/../../scripts/ready-set.sh" <owner>/<repo> <parent> --slug=<slug>
   ```

   `ready` is what may be dispatched, in the parent's order. `waiting` gives each
   held child's `reasons`: `blocked` (with the `blocked_by` URLs, which include
   a blocker closed as not planned), `claimed`, and, when `parent.spec_review`
   is true, `no-ready-verdict` or `design-not-ready`, the parent's own latest
   verdict not reading `READY`. A
   `result=ERROR` (`bad-args`, `unsupported-forge`, `not-found`, `issue-query`,
   `issue-query-shape`, or `set-overflow`) means the set was not read: dispatch
   nothing, say so, and stop.
4. **`open=0`**: every child is closed. Go to "Project review".
5. **Dispatch** while fewer than three children are in flight, or the cap the
   operator set: take the next `ready` child, skipping any that a `decided` row
   still being applied reaches. Claim it first, with
   `claim-issue.sh <owner>/<repo> <child> --claim` and the same `--label` and
   `--stamp` as any claim. The claim is what keeps the next ready set from
   offering the child again, so a child whose claim did not return `result=OK`
   is not dispatched. Then run `SKILL.md`'s steps 3 to 5 on it and dispatch its
   author with `SKILL.md`'s recipe.
6. **Nothing in flight and nothing ready** means the run cannot progress: a
   cycle, a blocker outside the project, or a child held for a verdict or by
   someone else. Report each open child with its `reasons` and blockers, and
   stop.

A child is **in flight** while it is open and `claim-issue.sh` reads `OWN` on
it, and after it closes until its author has sent its final report and its
reviewer has ended. At that end, collect both agents' retrospectives and fold
their project-level items into the parent, per `references/retrospective.md`. A
child that closes without a merged PR: tell the operator.

## Waiting

`SKILL.md`'s three sources, with one issue watch over the whole set instead of
one per issue:

```bash
"<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <parent> <open child…> \
  --role=orchestrator --since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Re-arm it from its `── re-arm ──` line, which drops each issue that closed.
When the ready set shows an open child the watch does not cover, stop the watch
and arm a new one over the set, with `--since` from the stopped one's. Each PR
gets its own PR watch, as in `SKILL.md`.

Classify comments with `SKILL.md`'s table, and add these:

| Comment | What it is | Action |
| --- | --- | --- |
| a spec or set review verdict from the bot on a child | the child may be ready, or need its body answered | run the loop; a `CHANGES REQUESTED` from a re-review is handled in `references/design-change.md` |
| `**Project review, round <n>: …**` from the bot on the parent | the project's verdict | go to "Stop" |
| from the operator, on the parent | a decision, or a remark | a decision is a `decided` row, then `references/design-change.md` |

## Triage and the log

Triage against the parent's body first, its decisions with their rationale,
then the child's own body. `references/triage.md`'s allowlist applies, and a
decision the parent's log already holds, in its table or its archived rows, is
applied, citing its row.

Every row is written twice: the `Decision log:` comment on the child, as
`references/triage.md` gives it, and a row in the parent's decision-log table,
whose **Child** cell is the child's URL and whose **Entry** links that comment.
A decision about the parent alone, such as a systemic finding, has only the
table row.

You are the parent body's only writer. Edit it by reading the body, changing
it, and writing it back with `gh issue edit <parent> --body-file <file>`, and
re-read it just before each write.

**An escalation** waits on the operator. With `AskUserQuestion`, ask with it:
the loop pauses until they answer, and the events that arrived meanwhile are
handled after. Without it, post the question on the parent per
`issue-workflow`'s `references/delegated.md` and end the turn with it as your
report, leaving every watch armed. Only the child that asked waits; the rest of
the loop keeps moving, and the operator's answer arrives as a comment on the
parent through the set watch. Your own question's comment wakes the watch once.
You know its URL, so skip it.

## Systemic problems

Scan the parent's log at each loop, and each review round on a child's PR as
it arrives. Raise a finding when:

- questions from two different children cite the same `R#` or `D#`;
- one decision has been `applied` more than three times, or the parent's `Q5`
  threshold if it sets one;
- a reviewer finding recurs on a second child's PR, meaning the same `R#` or
  `D#` is cited, or the same file and the same kind of finding. Compare the
  round with the review rounds on the other children's PRs in this project.

A finding is a parent-table row, `proposed`, naming the IDs and the children
involved, and it escalates like any question. A pattern already in a row is not
raised again.

## Keep the log under the body limit

Before writing the parent, if its body passes 50,000 characters, move every
table row whose child is closed and whose state is final into one comment
opening `Decision log: archived rows`, and leave one row in its place pointing
at that comment. `proposed` rows and `decided` rows not yet applied stay.

## Restart on schedule

Every wake re-sends this session's whole context, so after 40 wakes, or at the
first context compaction, hand over to a fresh session. Wait until every author
in flight has its PR out of draft or is waiting on the operator, so a fresh
author can continue the pushed work. Then check every decision is in the
parent, stop your watches and subagents, and tell the operator that you are
restarting and why: they start a fresh session on the parent's URL, which
resumes from the parent and re-claims under "On start".

## Project review

When every child is closed, dispatch `reviewer` on the parent, in the
background:

> Act as the reviewer on `<parent URL>`, in `reviewer`'s issue mode. It is a
> tracking issue, so grade the whole project. You were dispatched by an
> orchestrator, so follow `issue-workflow`'s `references/delegated.md` wherever
> a skill asks the operator something.

Its verdict arrives on the parent through the set watch, now on the parent
alone.

## Stop

Stop on the project verdict, and never judge the end-to-end criteria yourself.
Write your own retrospective, once for the run, per
`references/retrospective.md`, with the parent as its issue. Report under `SKILL.md`'s three headings, covering every child: its PR, and
every escalation with its outcome. On `ACCEPTED`, tell the operator the project is
ready for closeout: "close out `<parent URL>`" (`references/closeout.md`). On
`CHANGES REQUESTED`, give the findings: what to build next is the operator's
call. The reviewer keeps watching the parent, to review the closeout PR.
