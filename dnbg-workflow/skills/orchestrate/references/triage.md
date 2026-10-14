# Orchestrate: triage and the decision log

Part of the `orchestrate` skill. Read this before answering the first question
an author asks; `SKILL.md` says when one arrives.

## What you may decide alone

Escalate by default. Answer a question yourself only when the answer is one of
these, and the issue's recorded rationale covers the case at hand rather than
merely mentioning it:

- **(a)** applying a decision whose recorded rationale names the case at hand,
  whether it is in the issue body, in its parent's body, or in an earlier
  `Decision log:` row on the issue;
- **(b)** choosing among options the design already ranks, or taking the default
  an open question states;
- **(c)** an implementation choice that changes no interface, contract,
  user-visible behavior, or acceptance criterion;
- **(d)** ordering and scheduling of work;
- **(e)** a question of fact about the tree or the forge's state, answered by
  checking it.

Everything else escalates, and these always do: a change to an external
contract or to user-visible behavior, a change of scope, a choice between
competing values, and anything that contradicts the design. So does a discovery
the issue's author could not have known about, because answering it is a new
decision rather than a lookup.

When the issue is a child of a tracking issue whose decisions state an
escalation allowlist of their own, that decision is the authority instead, and
a difference between the two is itself an escalation.

## The row

Every answer, escalation outcome, and application of a prior decision is one
comment on the issue. Its first line is fixed, so a scan can grep for it:

```
Decision log: <ID> — <state>
```

- **`<ID>`** is the decision the row records or applies. Cite an existing ID
  when there is one: a `D#` or `Q#` the issue or its parent defines, or the ID
  of an earlier row. A plain issue's sections carry no IDs, so a row applying
  one cites its heading, as in `Decision log: Proposed approach — applied`. A
  new decision takes the next unused `<n>-D<k>` on this
  issue, where `<n>` is the issue number, so it cannot collide with the parent's
  own IDs.
- **`<state>`** is `proposed` for a question escalated and not yet answered,
  `decided` for an answer given, and `applied` for an existing decision applied
  to a new case.

Below the first line, in this order:

- **Question** — the `Delegated question:` comment's URL, or the operator
  comment's URL when the decision came from one.
- **Answer** — the answer, in a sentence or two.
- **Basis** — the allowlist item it was decided under and the rationale it rests
  on, quoted or linked; or `operator`, with how they answered (in session, or
  the comment's URL).

A row under (a) names the decision it applies:

```
Decision log: D4 — applied

**Question:** https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>
**Answer:** Edit the body from the orchestrator only; the author proposes the change in its report.
**Basis:** allowlist (a). D4's rationale, "body edits are whole-body replaces and two writers clobber each other", names this case.
```

Under a tracking issue, each row is also a row of the parent's decision-log
table, per `references/multi-issue.md`.

An escalation gets two rows: `proposed` when you ask, and `decided` with the
operator's answer when it arrives. A restart reads a `proposed` row with nothing
after it as a question still waiting on the operator.

## Promote decided rows into the body

After a `decided` row, edit the issue body so a cold reader of it sees the
decision without the log: change the section the decision affects, such as the
"Proposed approach" or an acceptance criterion, and link the row. An `applied`
row changes nothing in the body, since the decision it applies is already there.
