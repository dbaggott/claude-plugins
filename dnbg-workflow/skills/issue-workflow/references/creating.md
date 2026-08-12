# Issue workflow: creating an issue

Part of the `issue-workflow` skill. Read this when filing or updating an issue;
`SKILL.md` carries the host check, the reference conventions, and the
maintenance sweep — all of which apply either way; `references/resolving.md`
covers picking an issue up.

## Creating issues

Issues must be **self-documenting** — a cold reader should understand the problem, the intended direction, and what "done" looks like without clicking through to other issues, PRs, or docs.

### Capture the direction, not just the problem

The single highest-value section. At creation time there is almost always a clear solution or direction in the surrounding context — a conversation, a review comment, code just explored. That context dies with the session; the issue body is the only carrier.

- **If a direction exists, a "Proposed approach" section is mandatory.** State the approach, the specific files/functions/modules involved, and any alternatives that were considered and rejected (with the reason — the rejection rationale is what stops the resolver from rediscovering the dead end).
- **Anchors are verified, not recalled.** Every file path, function name, schema field, or external identifier named in the body is checked against the current tree (or the external source) before filing — and the body says so ("Verified present at `src/auth.ts:40`"). One wrong anchor costs more than none: the resolver loses trust in the whole body and falls back to re-researching everything, the exact failure this skill exists to prevent.
- **If the direction is mostly set but real unknowns remain, add an "Open questions / decisions for the implementer" section.** Frame each as a decision with a default — "X or Y — default X because Z" — never as an open musing. This is the common shape (90% directed, two or three bounded unknowns); it is not the same as open-ended, and without the default form the resolver stalls or silently picks.
- **If the issue is genuinely open-ended, say so explicitly** — e.g. "No preferred approach; evaluate X vs Y and pick." That tells the resolver the open-endedness is intentional, not an omission, and licenses the design exploration.
- **Acceptance criteria and known constraints belong inline.** "See the linked PR for the design" is not enough — paste the relevant parts.
- **Every acceptance criterion must be runnable at the end of *this* issue.** Litmus: "can this be checked against the merge commit of this issue alone?" A criterion needing a route, schema, or operation that another issue introduces is unrunnable here, and becomes either a test nobody can write or a checkbox ticked by inspection. Move it to the issue that supplies the missing piece, and leave a pointer so the coverage doesn't read as dropped. The corollary, for an invariant two issues share: **assert it in whichever issue introduces the operation that could break it**, not in the one that states it. Writing it into the issue that *owns* the invariant reads as thorough and is exactly the trap — that issue usually can't run it, so the guard ships untested in the issue carrying the actual risk.

### Inline summary over links

- If the relevant content is a schema, a reviewer's specific concern, or a short code excerpt, **paste it into the issue body** and cite the source URL beneath it — don't rely on the reader clicking through.
- Include a link only when the linked content is genuinely irreducible (a long proposal doc, a non-trivial PR diff, audit logs). Even then, summarize its key conclusions inline; the link is supplementary.
- Don't link to recently-merged PRs as a substitute for describing what changed. The resolver shouldn't need to read a diff to understand the issue's context.
- **Carry conclusions, not the investigation story.** "Inline over links" means each conclusion plus its minimal supporting fact ("Evidence: the retry path drops the dedup key — see `queue.go:112`"), not the session narrative that produced it. The resolver needs what's true and why it matters, not how it was discovered.

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

The `assigned:*` claim labels are a third axis, applied by the claiming flow in `references/resolving.md` rather than here.

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
