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
4. **Review the design.** Read the parent's body as `SKILL.md`'s step 5 reads
   an issue, then run `issue-workflow`'s critical review on it: the parent is
   yours, not an author's, and a design you believe is wrong is an escalation
   before any dispatch.
5. **Arm the set watch** (below, under the first-arm rule), then run the loop. With every child already
   closed, the loop goes straight to the closeout, whose step 1 continues a
   predecessor's closeout PR. A parent already closed by that PR's merge has
   only "Stop" left.

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
4. **`open=0`**: every child is closed. Once every child's agents have ended,
   resolve the parent through its closeout PR, per `references/closeout.md`.
5. **Dispatch** while fewer than three children are in flight, or the cap the
   operator set: take the next `ready` child, skipping any that a `decided` row
   still being applied reaches. Claim it first, with
   `claim-issue.sh <owner>/<repo> <child> --claim` and the same `--label` and
   `--stamp` as any claim. The claim is what keeps the next ready set from
   offering the child again, so a child whose claim did not return `result=OK`
   is not dispatched. Then run `SKILL.md`'s steps 3 to 5 on it and dispatch its
   author with `SKILL.md`'s recipe.
6. **Nothing in flight, nothing ready, and no `decided` row still being
   applied** means the run cannot progress: a cycle, a blocker outside the
   project, or a child held for a verdict or by someone else. Report each open
   child with its `reasons` and blockers, and stop. While a row is still being
   applied, its re-review's verdict reaches you through the set watch, so wait
   for it.

A child is **in flight** while it is open and `claim-issue.sh` reads `OWN` on
it, and after it closes until its author has sent its final report and its
reviewer has ended. At that end, collect both agents' retrospectives and fold
their project-level items into the parent, per `references/retrospective.md`. A
child that closes without a merged PR: tell the operator.

## Waiting

`SKILL.md`'s two sources, with one issue watch over the whole set instead of
one per issue:

```bash
"<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <parent> <open child…> \
  --role=orchestrator --since=<SKILL.md step 1's fetch-issue-set.sh now=>
```

Arm it with `--exclude` carrying the URLs of the PRs step 3 found on each
child, and re-arm it from its `── re-arm ──` line, which drops each issue
that closed. When the ready set shows an open child the watch does not cover, stop the watch
and arm a new one over the set, with `--since` and `--exclude` from the stopped
one's, adding the new child's PR URLs.

Keep, per child, what its author's last report said it is waiting for, when the
report ends on a wait rather than a question or a result. Several authors can
be waiting at once, and that record is what
https://github.com/dbaggott/claude-plugins/issues/260's resume rule reads.

Classify comments with `SKILL.md`'s table, and add these:

| Comment | What it is | Action |
| --- | --- | --- |
| a spec or set review verdict from the bot on a child | the child may be ready, or need its body answered | run the loop; a `CHANGES REQUESTED` from a re-review is handled in `references/design-change.md` |
| `**Project review, round <n>: …**` from the bot on the parent | the link to a round of the closeout PR's review | none; you handle the round from the PR, per `references/closeout.md` |
| from the operator, on the parent | a decision, or a remark | a decision is a `decided` row, then `references/design-change.md` |

## Triage and the log

Triage against the parent's body first, its decisions with their rationale,
then the child's own body. `references/triage.md`'s allowlist applies, and a
decision the parent's log already holds, in its table or its archived rows, is
applied, citing its row.

Every row is written twice: the `Decision log:` comment on the child, as
`references/triage.md` gives it, and a row in the parent's decision-log table,
whose **Child** cell is the child's URL and whose **Entry** links that comment.
A decision raised on the parent, such as an operator comment there or a
systemic finding, has only the table row, and reaches a child through
`references/design-change.md`, which promotes it into the child's body.

Append the table row with:

```bash
"<skill-dir>/../../scripts/log-row.sh" <owner>/<repo> <parent> --table="Decision log" \
  --row='| <date> | <ID> | <child URL or —> | <entry> | <state> |'
```

`result=OK` means the row is in the body. A re-run never adds it twice, so on
`write-lost`, `write` or `issue-query` run it once more, and escalate if it
fails again. `section-missing` or `table-missing` means the parent has no
decision log to append to, which is an escalation.

Every `decided` row, an answer to one child's question included, is finished
through `references/design-change.md`, whose last step marks it `applied`. A
row left at `decided` reads as unfinished work on every later loop and restart.

You are the parent body's only writer. A child's body is its author's, per
`SKILL.md`; you edit one only in a design change's sweep of a child not yet
dispatched (`references/design-change.md`). Any other body edit, a row's
state cell included, is reading the body, changing it, and writing it back with
`gh issue edit <n> --body-file <file>`, re-read just before each write.

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

After each write to the parent, if its body passes 50,000 characters, which
`log-row.sh` prints as `body_chars`, move every table row whose child is closed
and whose state is final into one comment opening `Decision log: archived
rows`, and leave one row in its place pointing at that comment. `proposed` rows and `decided` rows not yet applied stay.

## Stop

Stop when the closeout PR has merged and its post-merge cleanup is done, or
when the operator says to stop after it closed unmerged. Never judge the
end-to-end criteria yourself: the reviewer grades them on that PR. Report under
`SKILL.md`'s three headings, covering every child, with its PR, the closeout PR,
and every escalation with its outcome.
