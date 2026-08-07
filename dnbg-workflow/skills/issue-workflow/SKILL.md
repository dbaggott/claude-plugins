---
name: issue-workflow
description: How to create, maintain, and pick up GitHub issues so context survives the handoff — self-documenting issue bodies (verified anchors, proposed approach, decisions-with-defaults, acceptance criteria inline and runnable at the end of the issue that carries them, state-independent cross-references), labeling along the type and `area:*` (subsystem) axes, required-vs-optional cross-references, keeping the body current as work ships, claiming an issue on pickup (assignee + `assigned:claude-code` label + comment) after checking it isn't already claimed, and disciplined link-following plus a freshness probe when resolving, critically reviewing the issue itself (misdiagnosis, symptom-vs-root-cause, wrong approach, false premise) before writing code, and getting operator buy-in on any approach you have to design rather than implementing it unasked, including surfacing substantive design changes that emerge mid-implementation in chat before a PR leaves draft. Load when about to create a GitHub issue (any `gh issue create`), file follow-up work as an issue, update an issue after partial progress or a referenced PR closing, pick up/resolve an existing issue named by number or URL ("resolve #245", "do issue 245", "work on <issue URL>" — those bare forms are user phrasing, not a license to emit bare `#N` yourself; load this before reading any file or opening a worktree, not after), or assign/dispatch an issue to anyone (person or bot). The pickup trigger is an issue being named, not the user's choice of words. Skip for merely referencing an issue.
---

# Issue workflow

An issue is a handoff: the session that creates it has rich context (the conversation, the code just read, the direction just agreed), and the session that resolves it has only the issue body. Whoever resolves it — a fresh interactive session, an automated agent, a human — reads that body cold. The failure modes this skill exists to prevent:

- **Wasted research.** An issue body full of unlabeled cross-references forces the resolver to either follow every link (burning context budget before any code changes) or skip them (and maybe miss the one that mattered).
- **Wrong implementation path.** An issue that was perfectly clear *in the context of its creation* reads as open-ended to a cold resolver, who then picks a different approach than the one everyone had in mind. The resolution should not depend on which agent happens to pick the issue up.
- **Rotted handoff.** The body was accurate at creation, then the world changed — part of the work shipped, a referenced PR closed, new evidence landed in a comment — and a cold resolver faithfully implements stale truth.

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
- **Related (optional)** — background only. Add the literal instruction "do not read unless blocked" so a resolver under the link-following discipline below knows these are skippable.

An unlabeled reference defaults to looking load-bearing, so the resolver pays for it either way — label or omit.

All references use full GitHub URLs (see "Referencing issues and PRs" below).

### Write state-independent references

When the body's truth depends on another issue/PR's future state, phrase it as a conditional that holds in **every** state — "while X exists", "any run without a registration row" — rather than a snapshot of the current state — "until X lands", "once X merges". A snapshot owes a maintenance sweep when the world changes (and the sweep is owed even if the issue is never touched again, which the touch-triggered maintenance model below can't cover); a conditional never does.

Same discipline for case lists: state the **contract** ("the fallback covers any request with no session row") and mark any enumeration as illustrative ("the cases below are illustrations, not an enumeration to maintain") — so membership changes elsewhere can't stale the body.

Litmus test before filing: for each cross-reference, ask "if the referenced thing resolves first, does this body need editing?" If yes, rephrase until the answer is no.

### Label the issue

Labels sort along independent axes; an issue carries one from each that applies, not one total:

- **Type** — what kind of work it is: `bug`, `enhancement`, `documentation`, etc. Apply exactly one. This is the axis a triager filters on first, so an unlabeled issue is effectively invisible to that pass.
- **Area** (`area:*`) — which subsystem it touches. The component axis that keeps a growing backlog scannable. Apply at least one; an issue genuinely spanning two subsystems gets both. The valid set is **per-repo and self-describing**: run `gh label list --repo <repo> --search area` and read each label's description — that listing is the catalog, not anything enumerated here, so it never goes stale against this skill. When none fits and the issue clearly belongs to a *recurring* subsystem, **propose** a new `area:<kebab>` label with a one-line description and get the operator's confirmation before creating it (`gh label create --repo <repo> --color <hex> --description "..."`). Don't mint area labels unilaterally — the per-repo set stays human-curated, and ad-hoc creation fragments the namespace (`area:db` vs `area:database`).

The `assigned:*` claim labels are a third axis, applied by the claiming flow under "Picking up an issue" below rather than here.

## Maintaining issues

The cheapest sweep is the one never owed — write state-independent references (above) and most of this section never triggers. For the drift that remains:

**The body is the current truth; comments are history.** A cold resolver reads the body as "this is the work," so a body that has drifted from reality actively misleads — and no comment thread repairs that, because resolvers under the link-following discipline below won't reconstruct truth from a comment archaeology dig.

This isn't a standing patrol duty. The trigger is touching the issue for any reason — commenting on it, shipping part of it, closing or merging a PR it references. For the merge case, find the issues to sweep via `gh pr view <n> --json closingIssuesReferences` (the keyword-linked set) plus any issue URLs in the PR description — this sweep is maintenance, not context exploration, so the depth-1 reading cap in "Picking up an issue" below doesn't apply to it. When triggered, bring the body back to current truth before moving on:

- **Status-mark shipped work.** If part of the issue has landed, mark that section shipped (with the PR URL) instead of leaving it presented as open work — otherwise a cold resolver re-implements it.
- **Promote comment-borne facts into the body.** New evidence or decisions that arrived as comments get folded into the body. A fact that lives only in a comment is invisible to the handoff.
- **Sweep cross-references on state changes.** When a referenced PR or issue closes or is superseded, update the body text that depends on it — a "how to apply" that names a mechanism from a closed PR sends the resolver hunting for a file that doesn't exist.

## Picking up an issue

When resolving an issue, the body is the contract — once the freshness probe below passes, trust the creator's labeling and don't re-research what's already inline. Trusting the inline research is not the same as accepting the issue's conclusions: the body still gets a critical review (below) before any code, the way code gets one before it merges.

### Claim it first — and check it isn't already claimed

An issue being worked must look in-progress from the outside, or the next session (or agent, or human) picks it up in parallel. Both halves apply at pickup time, before any implementation:

**1. Check for an existing claim.** One call returns all three in-progress signals:

```bash
gh issue view <n> --repo <repo> --json assignees,labels,closedByPullRequestsReferences
```

The issue is already in progress if any of: an assignee is set, **any** `assigned:*` label is present, or `closedByPullRequestsReferences` lists a PR that is still open (the field omits PR state — check with `gh pr view <number> --json state`). If so, don't start — surface what you found (which signal, which PR, how old the claim comment is — its timestamp comes from a follow-up `gh issue view <n> --json comments`, needed only on a hit) and ask the operator; in an unattended run, ask via a comment on the issue and stop. An open issue with an `assigned:*` label but **no** open linked PR and an old claim comment is the stale-claim signature — the claiming session probably died without finishing. Say so when asking, but proceeding past someone's claim is the operator's call, never yours.

The `assigned:*` namespace is deliberately open: whatever else works these repos — another agent, a bot, a teammate's tooling — claims with its own label in that namespace, and the check above matches the prefix rather than an enumerated list, so a new claimant needs no change here.

One exception: a claim of `@me` + `assigned:claude-code` may be this very session's earlier mark, or a sibling session run by the same operator — mechanically indistinguishable, since every session runs under the operator's account. Interactively, the dispatch itself disambiguates: the operator can see their own sessions, so note the existing claim in one line and proceed. In an unattended run there is no operator watching — still stop and ask via a comment.

The same check guards the dispatch direction: before routing an issue to anyone else — assigning a person, applying another agent's `assigned:*` label — run it and surface any existing claim before applying the new one.

**2. Claim it.** Three marks, each serving a different reader:

```bash
gh label create "assigned:claude-code" --repo <repo> --color BFD4F2 --description "Claimed by a Claude Code session" --force  # idempotent; no-op when the label exists
gh issue edit <n> --repo <repo> --add-assignee "@me" --add-label "assigned:claude-code"
gh issue comment <n> --repo <repo> --body "Claimed by a Claude Code session."
```

- The **assignee** makes the claim visible in issue lists and on the issue page.
- The **label** disambiguates what the assignee can't: sessions run under the operator's account, so assignee-alone could mean "the operator will get to this someday". `assigned:claude-code` means a session took it. The unconditional `gh label create --force` makes the block work first-try in any repo.
- The **comment** timestamps the claim — GitHub's own comment timestamp, no date in the body needed — which is what makes staleness detectable later.

Claims are never cleaned up. Once a linked draft PR exists it supersedes the claim as the in-progress signal, and when the issue closes, closed is closed regardless of labels. A lingering `assigned:*` label on an open issue is informative, not litter — it is exactly what makes the stale-claim signature above detectable.

### Working the issue

- **Read the issue body first.** It often contains enough context inline; links are usually supplementary, not load-bearing.
- **Run a cheap freshness probe before implementing.** Bodies rot: work partially ships, referenced mechanisms get superseded. Mechanically check the body's anchors — do the named files/functions exist in the current tree; are referenced PRs in the state the body implies (`gh pr view --json state`)? This is existence/state checking, not re-research — don't read content beyond what the probe needs. If the body contradicts the tree, surface the contradiction instead of proceeding: the issue may be half-shipped, and faithfully implementing it duplicates landed work.
- **Follow a link only if BOTH are true:**
  1. The current context doesn't answer a specific question you need to proceed (e.g. "what schema does the new column have?", not "what's the general background?").
  2. The link is in "Required reading", or is explicitly called out as holding the answer.
- **Hard recursion cap at depth 1.** If a followed link contains another link, stop. If a second hop seems genuinely necessary, ask the operator the specific question instead (in an unattended run, ask via a comment on the issue) — a human can answer it or point at the one piece of context that matters, cheaper than transitively reading three more linked PRs.
- **Prefer one targeted fetch over many.** Need one file from a linked PR? Fetch it directly (`gh api /repos/.../contents/<path>`) rather than reading the whole PR.

Anti-patterns:

- Reading every PR in a "Related (optional)" section.
- Reading a linked PR's full diff when only its description is relevant.
- Following links transitively (issue → PR → design doc → discussion) when the original issue already has enough context.

If unsure whether a link is critical, lean toward NOT following — ask the operator if the gap actually blocks progress.

### Review the issue critically before implementing it

An issue is written by a fallible author, the same as code — and it earns the same scrutiny: a review pass *before* any code is written, not deference. The freshness probe above asks "is the body still true to the tree?"; this asks the prior question, "was the body ever right?" The two are independent — an issue can be perfectly current and still misdiagnosed.

This pass is mandatory and applies to **every** issue, including a fully-researched one with a verified "Proposed approach" — a confident, well-anchored body can still be confidently wrong, and a clean freshness probe is no substitute for it. It is not a rubber stamp: "passes review" is a conclusion you reached by actually probing the body, not the default you fall to when nothing jumps out. Probe for:

- **Misidentified problem** — the reported symptom is real but the stated cause is wrong.
- **Symptom, not root cause** — the proposed fix papers over a downstream effect; the real defect is upstream and will resurface.
- **Wrong approach** — the problem is real and correctly diagnosed, but the proposed direction is costlier, less safe, or less aligned with the code than an alternative.
- **False premise** — the issue assumes a behavior, constraint, or code structure that doesn't actually hold. Verify the load-bearing *assumptions* against the tree, not just the anchors: that anchors exist is the freshness probe's job; whether the claim *about* them holds is this one's.

The output is a position: the issue is sound and you'll implement it, or it has a problem you can name. When you find a problem, surface it to the operator — don't silently re-route (the operator may know something the body doesn't, and the divergence is itself a design decision; see below) and don't faithfully implement what you believe is wrong. In an unattended run, raise the concern as a comment on the issue and stop.

### Match your handling to how grounded the issue is

Issues arrive at two depths, and what the resolver owes differs by depth:

- **Grounded** — the research is done and the approach is articulated against real code (a verified "Proposed approach"). Once the critical review above passes, implement that approach; don't treat a settled direction as one option among many or redesign it for taste.
- **Under-researched** — the issue names a real problem or goal, perhaps with implementation hints, but no code-grounded proposal. Here *you* are doing the design the creator didn't: investigating the code, weighing options, and forming the approach. That approach is a new decision, not a restatement of the issue.

**When you do the design, get buy-in before implementing it.** Make the operator aware of the situation — which depth the issue is, what the critical review found, and the approach you propose — and get approval before writing code. The same gate fires when the critical review re-routes a grounded issue: diverging from the stated direction is a design decision the creator never made, so it needs sign-off. Frame the ask as a recommendation with the alternatives and your reasoning, not an open question.

A grounded issue that passes the critical review cleanly needs no separate approval step — the creator already made the design decision and the review is the check on it. The approval gate is for design *you* introduce, not a checkpoint on every pickup. But "no separate approval" is not licence to rush to "grounded, proceed" by skimping the review — the gate is cheap because the review was real, not because it was skipped.

In an unattended run there is no operator to approve: post the proposed approach (and any critical-review concern) as a comment on the issue and stop — the same stop the already-claimed and failed-freshness-probe cases trigger. Designing and implementing in one unattended shot is exactly the path that ships a confident wrong approach with no review gate.

### Surface design changes that emerge mid-implementation

The buy-in gates above fire *before* code — at pickup, on an under-researched issue, or when the critical review re-routes a grounded one. But design decisions also surface *during* implementation: you start building the agreed approach, then hit a wall, find a better path, or discover a contract has to change, and you course-correct. That mid-flight change had no gate — the operator signed off on the issue's design (or the one agreed at pickup), not this one. Left unsurfaced, it's discovered at review or manual-test time, after the change and any rework are already paid for and after review ran against a design no one approved — the latency this rule exists to remove.

A **substantive** design change is one that departs from the issue's described approach, alters an external contract or interface, or otherwise changes what a reviewer or manual tester would evaluate. Routine implementation choices are not this; don't announce every decision. The litmus: *would the operator be surprised to learn this at review time?*

**Surface a substantive change clearly in chat before you move the PR out of draft** — state what changed from the agreed/issue design and why. The draft→ready transition (the `git-workflow` send-to-review picker) is the gate: it's the moment the operator's attention, the reviewer's, and manual testing all turn to the work, so the notification must come *before* that ask, not be folded silently into the send-to-review step. Recording it in the PR body too (per `git-workflow`'s "surface gaps" rule) is necessary but not sufficient — the PR body is read at review time, which is exactly the latency being removed; the chat notification before send-to-review is what's additional. In an unattended run, post the change and rationale as a comment on the issue before marking the PR ready.

## Referencing issues and PRs

Always use the full GitHub URL (`https://github.com/<owner>/<repo>/issues/19`, `https://github.com/<owner>/<repo>/pull/35`) — never bare `#19` or `<owner>/<repo>#35`. Two reasons:

- **Ambiguity.** A bare number only resolves inside the repo it was written in; the same text pasted into chat, another repo's issue, or a summary file points nowhere.
- **Clickability.** Only full URLs are clickable on every surface. Chat's markdown renderer does link `owner/repo#N`, but raw terminal text (`gh pr view` / `gh issue view` output, commit messages) gets only the terminal's URL matcher, which generally requires a scheme. References get copied between surfaces, so the chat-only form degrades in transit.

Nothing is lost on the web side: github.com renders full URLs to its own issues/PRs as the short `#19`-style link automatically.

When constructing a URL from a bare number of unknown type, use the `/issues/N` path — github.com redirects `/issues/N` ↔ `/pull/N` in both directions, so the path segment never has to match the artifact type.

This applies to every user-facing surface — chat, issue bodies, PR descriptions, commit messages, comments. Memory files are the exception (Claude-context, not rendered to users).
