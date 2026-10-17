# Issue workflow: creating an issue

Part of the `issue-workflow` skill. Read this when filing or updating an issue;
`SKILL.md` carries the host check, the reference conventions, and the
maintenance sweep — all of which apply either way; `references/claiming.md`
and `references/resolving.md` cover picking an issue up.

## Creating issues

Issues must be **self-documenting** — a cold reader should understand the problem, the intended direction, and what "done" looks like without clicking through to other issues, PRs, or docs.

A **tracking issue** — a body that is a project's design, parent of the issues implementing it — has its own shape and IDs: `references/tracking-issue.md`. Turning an accepted one into its children is `references/decomposing.md`.

### Capture the direction, not just the problem

The single highest-value section. At creation time there is almost always a clear solution or direction in the surrounding context — a conversation, a review comment, code just explored. That context dies with the session; the issue body is the only carrier.

- **If a direction exists, a "Proposed approach" section is mandatory.** State the approach, the specific files/functions/modules involved, and any alternatives that were considered and rejected (with the reason — the rejection rationale is what stops the resolver from rediscovering the dead end).
- **Anchors are verified, not recalled.** Every file path, function name, schema field, or external identifier named in the body is checked against the current tree (or the external source) before filing — and the body says so ("Verified present at `src/auth.ts:40`"). One wrong anchor costs more than none: the resolver loses trust in the whole body and falls back to re-researching everything, the exact failure this skill exists to prevent.
- **If the direction is mostly set but real unknowns remain, add an "Open questions / decisions for the implementer" section.** Frame each as a decision with a default — "X or Y — default X because Z" — never as an open musing. This is the common shape (90% directed, two or three bounded unknowns); it is not the same as open-ended, and without the default form the resolver stalls or silently picks.
- **If the issue is genuinely open-ended, say so explicitly** — e.g. "No preferred approach; evaluate X vs Y and pick." That tells the resolver the open-endedness is intentional, not an omission, and licenses the design exploration.
- **Acceptance criteria and known constraints belong inline.** "See the linked PR for the design" is not enough — paste the relevant parts.
- **Every acceptance criterion must be runnable at the end of *this* issue.** Litmus: "can this be checked against the merge commit of this issue alone?" A criterion needing a route, schema, or operation that another issue introduces is unrunnable here, and becomes either a test nobody can write or a checkbox ticked by inspection. Move it to the issue that supplies the missing piece, and leave a pointer so the coverage doesn't read as dropped. The corollary, for an invariant two issues share: **assert it in whichever issue introduces the operation that could break it**, not in the one that states it. Writing it into the issue that *owns* the invariant reads as thorough and is exactly the trap — that issue usually can't run it, so the guard ships untested in the issue carrying the actual risk.
- **A criterion met by a recorded run names what invalidates the run.** An eval or a live exercise is met by a run recorded on the PR, and "at the merge commit" leaves every later commit asking whether to run it again. Name the paths whose change can void it and, in a sentence, the behavior the run proves: "one passing run of the `<x>` eval, recorded on the PR, proving the stop, one feedback round, and the resumption; re-run after a change under `tests/evals/<x>/` or the skills it loads, unless the PR's record shows the change leaves that behavior as it was". A commit touching none of the paths leaves the run standing, and so does one under them that the author's record on the PR shows leaves the named behavior as it was (`references/resolving.md`). Where the clause names paths alone, any change under them voids the run.

### Declare an operator check before review

When the proposed approach changes anything a person sees or interacts with when
it runs (pages, components, templates, styles, terminal screens), ask the operator
with `AskUserQuestion` whether they want to look at the work before it is
reviewed, with two options: **"Add the check"** and **"No check"**. When unsure
whether the approach does, ask; the cost is one picker. Without
`AskUserQuestion`, take the default, no check, and say so in the report: the
operator adds the section, or asks for the check when dispatching, when they
want the look.

On "Add the check", the body gets a section of its own, outside the acceptance
criteria:

```markdown
## Operator check before review

<the recipe for bringing the work up, run from the worktree: the command, the
project skill, or the port; and what to look at>
```

The resolver stops there once the work is complete, before its self-review
(`git-workflow`, "Operator check before review"), and the operator's feedback
goes back to it until they say proceed. The section is a declaration, not an
acceptance criterion: the reviewer grades nothing in it (`reviewer`'s
`references/issue-mode.md`). The recipe's command is an anchor, verified before
filing like any other.

### Inline summary over links

- If the relevant content is a schema, a reviewer's specific concern, or a short code excerpt, **paste it into the issue body** and cite the source URL beneath it — don't rely on the reader clicking through.
- Include a link only when the linked content is genuinely irreducible (a long proposal doc, a non-trivial PR diff, audit logs). Even then, summarize its key conclusions inline; the link is supplementary.
- Don't link to recently-merged PRs as a substitute for describing what changed. The resolver shouldn't need to read a diff to understand the issue's context.
- **Carry conclusions, not the investigation story.** "Inline over links" means each conclusion plus its minimal supporting fact ("Evidence: the retry path drops the dedup key — see `queue.go:112`"), not the session narrative that produced it. The resolver needs what's true and why it matters, not how it was discovered.
- **Don't argue for the issue's own shape.** Why this is one issue and not three, why it isn't a duplicate — the reader already holds the scoped artifact, so none of it changes what they do. Where such an argument carries a real constraint ("X cannot land before Y"), keep the constraint and attach it to the thing it constrains.

The asymmetry: writing a self-documenting issue costs the creator a few extra minutes once; an issue that requires N link-traversals costs *every* future reader the same N traversals.

### Label every cross-reference

Cross-references go in one of two explicitly-titled groups:

- **Required reading** — the resolver must read these before starting. Keep this list ruthlessly short; every entry is a context-budget tax on the resolver.
- **Related (optional)** — background only. Add the literal instruction "do not read unless blocked" so a resolver under the link-following discipline (`references/resolving.md`) knows these are skippable.

An unlabeled reference defaults to looking load-bearing, so the resolver pays for it either way — label or omit.

All references use full GitHub URLs (see "Referencing issues and PRs" in `SKILL.md`).

### Write state-independent references

When the body's truth depends on another issue/PR's future state, phrase it as a conditional that holds in **every** state — "while X exists", "any run without a registration row" — rather than a snapshot of the current state — "until X lands", "once X merges". A snapshot owes a maintenance sweep when the world changes (and the sweep is owed even if the issue is never touched again, which the touch-triggered model in "Maintaining issues" (`SKILL.md`) can't cover); a conditional never does.

Same discipline for case lists: state the **contract** ("the fallback covers any request with no session row") and mark any enumeration as illustrative ("the cases below are illustrations, not an enumeration to maintain") — so membership changes elsewhere can't stale the body.

Litmus test before filing: for each cross-reference, ask "if the referenced thing resolves first, does this body need editing?" If yes, rephrase until the answer is no.

### Label the issue

Labels sort along independent axes; an issue carries one from each that applies, not one total:

- **Type** — what kind of work it is: `bug`, `enhancement`, `documentation`, etc. Apply exactly one. This is the axis a triager filters on first, so an unlabeled issue is effectively invisible to that pass.
- **Area** (`area:*`) — which subsystem it touches. The component axis that keeps a growing backlog scannable. Apply at least one; an issue genuinely spanning two subsystems gets both. The valid set is **per-repo and self-describing**: run `gh label list --repo <repo> --search area` and read each label's description — that listing is the catalog, not anything enumerated here, so it never goes stale against this skill. When none fits and the issue clearly belongs to a *recurring* subsystem, **propose** a new `area:<kebab>` label with a one-line description and get the operator's confirmation before creating it (`gh label create --repo <repo> --color <hex> --description "..."`). Don't mint area labels unilaterally — the per-repo set stays human-curated, and ad-hoc creation fragments the namespace (`area:db` vs `area:database`).

Two more axes are applied by other flows rather than here:

- **Claim** (`assigned:*`) — who is working it, applied by the claiming flow in `references/claiming.md`.
- **Project** (`project:<slug>`) — which tracking issue it belongs to, on the parent and every child. `references/decomposing.md` mints it and applies it when the children are filed. A child filed later carries it too, and its title takes the parent's `[<slug>]` tag. A plain issue carries none.

### Reporting a gap upstream

An issue filed against someone else's project — reporting that tooling you
installed doesn't fit your case — is governed by the always-on rule "When
shipped tooling doesn't fit, tell the user", not by the operator's own
conventions. Two constraints that don't apply to an issue in your own repo:
it is published under the user's identity to a project they don't control, so
it is filed only if they ask for it and only after they have approved the exact
text; and the body is written from the **generic** case, so the session that
exposed the gap contributes the shape of the problem and none of its content.
Everything above about being self-documenting still applies to what remains.
