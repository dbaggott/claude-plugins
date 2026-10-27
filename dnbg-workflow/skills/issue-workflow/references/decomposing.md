# Issue workflow: decomposing a tracking issue

Part of the `issue-workflow` skill. Read this when turning an accepted
**tracking issue** into the child issues that implement it.
`references/tracking-issue.md` defines the parent's shape and IDs, and
`references/creating.md` governs every child body.

The input is a tracking issue whose decision log carries its acceptance row
(`tracking-issue.md`, "Acceptance"). Without that row the design can still
change under you, so stop and say so rather than decomposing it. A `decided`
row whose entry the body does not yet carry is applied to the body before
step 1, under `tracking-issue.md`'s ID rules and linking the row from each
changed entry, since step 5 marks it `applied`.

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
- **Two children that rewrite the same section are not independent**, even
  when neither needs the other to exist. Before marking two children
  independent, list the sections each one's requirements change, by file and
  heading or step (`closeout.md` step 5). Different sections of one file stay
  independent: git merges them, and their meanings cannot collide. A file whose
  total size a repo test caps is one section, since two children that each add
  to it can pass alone and fail together. Where the lists share a section,
  record one of:
  - one child depends on the other;
  - the shared text moves into one child;
  - both children's Proposed approach names the shared section and says which
    child owns which sentences of it.

## 2. Write each child's title and body

The title is `[<slug>] <description>`, with the parent's slug, read from its
own title (`tracking-issue.md`, "Declare it"). A parent filed without a tag
gets one first: choose the slug there and retitle the parent to that form. The
body is per `creating.md`, opening with the parent and three fixed lines:

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

An `A<n>` met by a run, such as an eval or a live exercise, names who records
it: the contributing child that depends on all the others, whose own
criteria then include "run and record A<n>", or the closeout PR's author, who
runs it before the project review. It also names the paths invalidating the
run and the behavior it proves, per `creating.md`.

## 4. File the children and set their relationships

Children live in the parent's repository. Before filing any, mint the project
label there and put it on the parent:

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner/repo> -- \
  gh label create "project:<slug>" --repo <owner/repo> --force --color 5319E7 \
  --description "Tracked by <parent URL>"
"<skill-dir>/../../scripts/as-role.sh" author <owner/repo> -- \
  gh issue edit <parent> --repo <owner/repo> --add-label "project:<slug>"
```

`--force` updates a label that already exists rather than failing on it, so run
the call without checking for the label first.

File in dependency order, blockers first, so every `Depends on` line names real
URLs. A body that mentions a child filed after it, outside `Depends on`, gets
that URL in an edit once the child exists. For each, file it per `creating.md`
(labels included, `project:<slug>` among them), then set its relationships with
one call:

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner/repo> -- \
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
- One decision-log row recording the filing, its Entry opening `Children
  filed`, state `applied`; and every `decided` row the children were written
  from set to `applied`, since the body and every child match it by
  construction. A row decided after step 2 began stays `decided` unless each
  child it reaches has been edited to match it.

## 6. Send the set to review

Hand the parent and its children to a set review per
`references/spec-review-rounds.md`, "Handing the issue to its reviewer", and
answer its rounds there. Say what follows it:
once every issue in the set reads `READY`, the next prompt is
`orchestrate <parent URL>`, in a fresh session, since it reads everything from
GitHub, and this session has nothing further to do.
