# Issue workflow: a tracking issue

Part of the `issue-workflow` skill. Read this when filing or maintaining a
**tracking issue**: an issue whose body is a project's design, and which is the
parent of the sub-issues that implement it. `references/creating.md` governs it
too — self-documenting, verified anchors, labelled cross-references — except
where this file says otherwise.

## Declare it

Start the body with the words `This is a **tracking issue**`, verbatim; the
rest of the sentence is yours. That opening is what routes a spec review of it
to the design checks, in `issue-reviewer`'s `references/design-review.md`.

## Sections

Required, in this order, even while a log is still empty:

- **Problem**, **Goals**, **Non-goals** — as in any issue.
- **Constraints** (`C#`) — verified facts the design rests on, each with the
  method that checked it, so it can be re-run when the world may have moved.
- **Requirements** (`R#`) — each one checkable: a reader can say whether a given
  result meets it.
- **Decisions** (`D#`) — format below.
- **Open questions** (`Q#`) — format below.
- **End-to-end acceptance criteria** (`A#`) — below.
- **Decision log** and **Friction log** — below.

Optional:

- **Candidate decomposition**, between the acceptance criteria and the decision
  log. Once children are filed, it is the table linking them, with each child's
  `Covers` and `Depends on`.
- **Required reading** and **Related (optional, do not read unless blocked)**, as
  `creating.md` describes.

Group requirements under sub-headings when the project has stages or areas; the
IDs stay one sequence across them.

## IDs

`C`, `R`, `D`, `Q` and `A`, numbered in order of creation within each prefix.
**Never renumber, never reuse, never delete.** Children, logs, comments and
reviews cite these IDs, and a renumbered or deleted entry silently re-points or
breaks every citation to it.

An entry that no longer holds stays where it is, marked:

- **Retired** — `Retired <date>: <why>, superseded by <ID>` (or `not replaced`).
  The original text stays, so an old citation still finds what it cited.
- **A settled open question** — `Decided <date> (<D#>)` in place of its default,
  pointing at the decision that settled it.

## Decisions

```markdown
- **D<n>. <The choice, as a statement.>** Because: <rationale>. Revisit if: <reversal condition>.
```

**The rationale is mandatory.** It is what a later reader extends to cases the
decision's text never mentions, so state it in terms that let them tell whether
a new case falls inside it.

**The reversal condition is a condition, or the literal `none identified`.**
Writing `none identified` is an answer; leaving the clause out is an omission. Do
not invent a condition to fill the slot: later readers trust it, and one nobody
believed sends them reopening a decision for no reason.

## Open questions

```markdown
- **Q<n>. <The question?>** Default: <answer>, because <reason>.
```

Every question carries a default, and a resolver may take it without asking.
A question with no default is one the design has not answered.

## Requirements and coverage

Once children are filed, every requirement not retired is covered in one of
these ways:

- a child names it in its `Covers` line;
- the requirement line ends in `*(end-to-end: A<n>)*` — only the whole project
  satisfies it, and `A<n>` is the end-to-end criterion that checks it;
- the requirement line ends in `*(deferred: <reason>)*` — deliberately not built
  in this project.

```markdown
- **R9.** <requirement text> *(end-to-end: A2)*
- **R14.** <requirement text> *(deferred: waits on the forge contract)*
```

Write the markings exactly as shown. They are a contract for any coverage check,
which matches them literally, so any other form reads as uncovered.

## End-to-end acceptance criteria

**These are exempt from `creating.md`'s rule that every criterion is runnable at
the issue's own merge.** They are, by design, the criteria no single child can
run. Each names what contributes to it — `Contributes: <children or R#s>`, or
the one requirement it checks named inline — so the children that must land
before it can run are known.

A child's own criteria still follow `creating.md`: runnable at that child's merge.

## Decision log

A table, newest row last:

```markdown
| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| 2026-10-14 | D11 | — | Allowlist written out (spec review round 1, 223-B1) | decided |
```

- **ID** — the entries the row affects (`D11`, `R7, R8`).
- **Child** — the child issue the row came from or changes, or `—`.
- **Entry** — what was decided, and where (the review finding, the comment, or
  "operator decision in session").
- **State** — `proposed` (raised, not yet settled), `decided` (settled; work may
  act on it now), or `applied` (the body and every affected child now match it).

A decision is acted on once it is `decided`; the body edit applying it is part of
the work, not a precondition for it.

## Friction log

Dated bullets recording where the **process** hurt — a skill that did not fit,
tooling that got in the way, a review step done by hand — as distinct from the
project's own problems. It is read into follow-up issues, or explicit drops, when
the project closes.

## Acceptance

A design is **accepted** when its latest spec review in design mode
(`issue-reviewer`'s `references/design-review.md`) is `READY` and the operator
has signed off. Record it as one decision-log row:

```markdown
| <date> | — | — | Design accepted: spec review READY (<round comment URL>), operator sign-off <where given> | decided |
```

Acceptance is that row. Nothing merges.

Until the row lands, any other edit to the body reopens the review. After it,
the design changes only through decision-log rows, and only the parts a change
touches are re-reviewed, not the whole body; acceptance stands.
