# Orchestrate: applying a design change

Part of the `orchestrate` skill. Read this when a row in a tracking issue's
decision log reaches `decided`, an answer to one child's question included, and
on start for every `decided` row not yet `applied`. A decision that changes
nothing beyond the asking child's body runs only steps 3 and 6. Such a row is work to finish, whoever started it, so each step below
checks the current state rather than assuming it is first to run. A row whose
entry the parent's body and every child it reaches already carry (step 2,
whose set serves every row of the pass) is not swept: set its state to
`applied` as step 6 does and post one line on the parent, `Decision log: <date>
<ID> set to applied, already in the body and every child`, as the orchestrator,
from a file in your draft directory:

```bash
"<skill-dir>/../../scripts/as-role.sh" orchestrator <owner>/<repo> -- \
  gh issue comment <parent> --repo <owner>/<repo> --body-file <file>
```

Every body edit below, the parent's and a child's, is the body edit in
`SKILL.md`'s "Write as the orchestrator", except step 6's state change, which
is `log-row.sh --set-state`.

Act on the row at once. The decision is the gate, and the edits below are part
of applying it, not a precondition for acting on it.

## 1. Change the parent's design

Edit the entries the decision changes: a decision, a requirement, an open
question settled by it (`Decided <date> (<D#>)` in place of its default), an
acceptance criterion. Follow `issue-workflow`'s `references/tracking-issue.md`:
never renumber or delete, and mark a superseded entry retired. Link the row from
each changed entry. Skip what already reads as the decision.

## 2. Find the children it reaches

```bash
"<skill-dir>/../../scripts/fetch-issue-set.sh" <owner>/<repo> <parent> \
  --json-out=<draft directory>/issue-set.json
```

The set goes to that file, for `jq` to read. A child is reached when its
`Covers` line or its body text cites an ID the decision changed. Match whole
IDs, so `R1` does not match `R12`. A `result=ERROR` means the set was not read:
stop and say so, since a sweep over part of the set leaves the rest silently
stale.

A closed child it reaches is shipped work that the decision may undo. Do not
edit it. Escalate whether it needs follow-up work.

## 3. Update each open child it reaches

Change the text of the child's body that the decision changes, and promote the
decision into it with a link to the row, as `references/triage.md` promotes a
decided row. The link is the child's record of it: a decision raised on the
parent gets no `Decision log:` comment on the children it reaches.

A child in flight is its author's to edit. `SendMessage` the author the
change, the edit it makes to the body, and the row's URL, and ask it to end its
turn once the edit is in. That report is when the child counts as updated, for
the steps below.

## 4. Re-review what changed materially

When the ready set's `parent.spec_review` is true, dispatch `issue-reviewer`, as
`dnbg-workflow:reviewer-orchestrated`, on the children whose acceptance
criteria changed, or whose body changed in a section their `Covers` line cites,
with its draft directory line (`git-workflow`'s "Draft files"). The rest are not
re-reviewed.

> Review `<child URLs>` as a set against their parent `<parent URL>`. This is a
> re-review after the design change in `<row link>`.
> Your draft directory: `<path>`

For an in-flight child, dispatch the re-review only once its author has
reported the edit. A child whose latest verdict is newer than its step 3 edit has had its
re-review. Answer the rounds as the bodies' writer, relaying them to the author
for a child in flight, per `issue-workflow`'s
`references/spec-review-rounds.md`, making its body edits and posting its
response comments as the orchestrator (`SKILL.md`, "Write as the
orchestrator"), except its wait: each round reaches you as
the `issue-reviewer`'s report, which ends on its own wait for your answer, so
read that report as a round to answer rather than as a wait; and except its
marking of the row `applied`, which is step 6 here; and except its close-out,
since yours is the orchestrator's at Stop. A finding that asks for a design change is
an escalation. A re-reviewed child is not dispatched until its latest verdict
reads `READY`.

When the re-review's reviewer ends, before step 6, carry its close-out to the
Stop report. A spec review writes no findings
entries, so nothing from it folds into the parent's findings log.

## 5. Tell the agents working on it

`SendMessage` the reviewer of every reached child in flight: the change, what
in its child's body it changed, and the row's URL. Step 3 already told the
author.

## 6. Mark the row applied

Once the parent and every reached open child match the decision, and every
re-review is `READY`, change the row's state cell to `applied`, giving each row
as it reads now (the text you appended, or read on start):

```bash
"<skill-dir>/../../scripts/log-row.sh" <owner>/<repo> <parent> --table="Decision log" \
  --set-state=applied \
  --row='| <date> | <ID> | <child URL or —> | <entry> | decided |' [--row=…] --as=orchestrator
```

It rewrites only each given row's state cell, the rows a pass applies together
in one write. `result=OK` means each row reads `applied`, so a re-run is safe;
other failures are handled as `references/multi-issue.md`'s append handles
them. `row-missing` means a row given is in the table in neither state: the
text you hold may be stale, as after a compaction, so read the parent's
decision-log table once and run it again with the rows as they read there.
Escalate if a row is not in the table, or the second run fails too.
