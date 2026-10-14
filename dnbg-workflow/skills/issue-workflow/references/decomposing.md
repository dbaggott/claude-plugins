# Issue workflow: decomposing a tracking issue

Part of the `issue-workflow` skill. Read this when turning an accepted
**tracking issue** into the child issues that implement it.
`references/tracking-issue.md` defines the parent's shape and IDs, and
`references/creating.md` governs every child body.

The input is a tracking issue whose decision log carries its acceptance row
(`tracking-issue.md`, "Acceptance"). Without that row the design can still
change under you, so stop and say so rather than decomposing it.

## 1. Group the requirements into children

If the parent has a **Candidate decomposition**, start from it. Otherwise group
the requirements by the stage they sit under and the files they would touch.
Either way, check the result against these, since a candidate table is the
design author's first guess:

- **Each child merges on its own and can be checked at its merge.** A group
  whose work only makes sense once another lands is either one child with it,
  or a child that depends on it.
- **Every requirement not retired is covered**: a child lists it in `Covers`,
  or the parent marks it `*(end-to-end: A<n>)*` or `*(deferred: <reason>)*`,
  written exactly as `tracking-issue.md` shows.
- **A cross-cutting requirement is covered by every child it applies to**, not
  by the first one. One child listing it reads as the whole project satisfying
  it.
- **Every dependency is explicit.** Child B depends on child A when B's work or
  B's acceptance criteria use something A introduces. Read each requirement and
  decision for what it needs to exist first; a dependency left implicit is
  found when B's criteria will not run. Two children that each need the other
  are one child, or a third holds what they share: the dependencies form no
  cycle.

## 2. Write each child's body

Per `creating.md`, opening with the parent and three fixed lines:

```markdown
Sub-issue of <parent URL> (the design). Section IDs below refer to that body.

**Covers:** R7, R8, R28
**Depends on:** <blocker URL>, <blocker URL>
```

- **`Covers`** lists requirement IDs only, including every cross-cutting
  requirement the child touches.
- **`Depends on`** lists each blocker's URL, or `none`. It mirrors the
  blocked-by relationships set in step 4, which are the source of truth; a
  mismatch between the two is a set-review finding, not something to repair
  silently.
- **Required reading** names the parent's sections by ID ("Parent: R7–R10, D2,
  Q1"), never the whole body.
- **Proposed approach** carries what the parent's decisions say about this
  child, inline. The child is resolved cold from its own body.

## 3. Keep every child criterion runnable at its own merge

`creating.md`'s rule, applied across the set: a criterion this child cannot run
at its merge, because it needs another child's work, does not go in this child.
It becomes an end-to-end criterion on the parent, `A<n>`, whose `Contributes:`
names this child and the others it needs. The child keeps a pointer to `A<n>`
so its coverage does not read as dropped.

## 4. File the children and set their relationships

File in dependency order, blockers first, so every `Depends on` line names real
URLs. A body that mentions a child filed after it, outside `Depends on`, gets
that URL in an edit once the child exists. Children live in the parent's
repository. For each, file it per
`creating.md` (labels included), then set its relationships with one call:

```bash
"<skill-dir>/../../scripts/set-issue-relations.sh" <owner/repo> <child> --parent=<parent> [--blocked-by=<n,...>]
```

`<skill-dir>` is this skill's announced Base directory. Read the result line:

- **`result=OK`** — the parent and every named blocker are in place.
- **`reason=parent-conflict`** — the child already belongs to another parent.
  Stop and surface it; moving an issue between projects is the operator's call
  (without `AskUserQuestion`: `references/delegated.md`).
- **`reason=parent-rejected`** or **`reason=blocked-by-rejected`** — the forge
  refused. Its message is on stderr. Fix the cause and run the same call again;
  a re-run writes only what is still missing.
- **`reason=issue-query`** — the child could not be read in full, so nothing
  was written.
- **Any other `reason`** — the call itself is wrong. Stop and surface it.

## 5. Bring the parent up to date

One body edit, after the last child is filed:

- The **Candidate decomposition** becomes the filed table: each child linked,
  with its `Covers` and `Depends on`.
- The coverage markings from step 1, and the end-to-end criteria from step 3.
- Every mention of a candidate child elsewhere in the body ("child 7") becomes
  that child's URL.
- One decision-log row recording the filing, state `applied`.

## 6. Send the set to review

Ask for a set review of the parent and its children with `issue-reviewer`, and
answer its rounds per `references/spec-review-rounds.md`. The children are ready
to pick up once that review converges `READY`.
