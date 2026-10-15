# Orchestrate: applying a design change

Part of the `orchestrate` skill. Read this when a row in a tracking issue's
decision log reaches `decided`, an answer to one child's question included, and
on start for every `decided` row not yet `applied`. A decision that changes
nothing beyond the asking child's body runs only steps 3 and 6. Such a row is work to finish, whoever started it, so each step below
checks the current state rather than assuming it is first to run.

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
"<skill-dir>/../../scripts/fetch-issue-set.sh" <owner>/<repo> <parent>
```

A child is reached when its `Covers` line or its body text cites an ID the
decision changed. Match whole IDs, so `R1` does not match `R12`. A
`result=ERROR` means the set was not read: stop and say so, since a sweep over
part of the set leaves the rest silently stale.

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
`dnbg-workflow:orchestrated-reviewer`, on the children whose acceptance
criteria changed, or whose body changed in a section their `Covers` line cites.
The rest are not re-reviewed.

> Review `<child URLs>` as a set against their parent `<parent URL>`. This is a
> re-review after the design change in `<row link>`. You were dispatched by an
> orchestrator, so follow `issue-workflow`'s `references/delegated.md`
> wherever a skill asks the operator something.

For an in-flight child, dispatch the re-review only once its author has
reported the edit. A child whose latest verdict is newer than its step 3 edit has had its
re-review. Answer the rounds as the bodies' writer, relaying them to the author
for a child in flight, per `issue-workflow`'s
`references/spec-review-rounds.md`. A finding that asks for a design change is
an escalation. A re-reviewed child is not dispatched until its latest verdict
reads `READY`.

## 5. Tell the agents working on it

`SendMessage` the reviewer of every reached child in flight: the change, what
in its child's body it changed, and the row's URL. Step 3 already told the
author.

## 6. Mark the row applied

Once the parent and every reached open child match the decision, and every
re-review is `READY`, change the row's state cell to `applied`.
