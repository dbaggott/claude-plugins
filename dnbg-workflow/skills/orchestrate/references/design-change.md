# Orchestrate: applying a design change

Part of the `orchestrate` skill. Read this when a row in a tracking issue's
decision log reaches `decided`, and on start for every `decided` row not yet
`applied`. Such a row is work to finish, whoever started it, so each step below
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
decided row.

## 4. Re-review what changed materially

When the ready set's `parent.spec_review` is true, dispatch `issue-reviewer` on
the children whose acceptance criteria changed, or whose body changed in a
section their `Covers` line cites. The rest are not re-reviewed.

> Review `<child URLs>` as a set against their parent `<parent URL>`. This is a
> re-review after the design change in `<row link>`. You were dispatched by an
> orchestrator, so follow `issue-workflow`'s `references/delegated.md`
> wherever a skill asks the operator something.

Answer its rounds as the bodies' writer, per `issue-workflow`'s
`references/spec-review-rounds.md`. A finding that asks for a design change is
an escalation. A re-reviewed child is not dispatched until its latest verdict
reads `READY`.

## 5. Tell the agents working on it

`SendMessage` the author and the reviewer of every reached child in flight: the
change, what in their child's body it changed, and the row's URL.

## 6. Mark the row applied

Once the parent and every reached open child match the decision, and every
re-review is `READY`, change the row's state cell to `applied`.
