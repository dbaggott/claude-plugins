# Git workflow: a review with findings

Part of the `git-workflow` skill. Read this when `references/review-received.md`
finds actionable findings in a round. Track whether the operator has opted in to
auto-handling for *this* PR, as that file says.

**Has findings, no sticky opt-in yet.** Post a summary of the review as a normal message, **then** call `AskUserQuestion` with three options (the tool auto-appends "Other" for anything else). The summary is the evidence the choice is made on — the operator decides fix-now vs defer from what you show them, usually without opening the review. A picker with no summary in front of it forces them to either pick blind or go read the review on GitHub themselves, which defeats the point of you driving the cycle.

Without `AskUserQuestion`, the summary and these options are the question in `<skill-dir>/../issue-workflow/references/delegated.md`. A dispatcher's "auto-handle the review" is a pre-answer for option 1.

The summary goes in the message body, before the tool call — the picker's `question` and option `description` fields are too small to carry it. Cover:

- The review state (APPROVED / CHANGES_REQUESTED / COMMENTED).
- Each actionable finding, one or two sentences: what the reviewer wants changed and where, plus your read when it affects the decision (trivial vs real rework, in-scope vs scope creep — the same inputs the recommendation logic below runs on).

Never call this picker without the summary in front of it — even when the findings are trivial or the right choice seems obvious. "Trivial" is your assessment, and the summary is how the operator checks it.

**The summary must be re-sendable.** The picker's question references the summary above it, but the operator may not be able to see that summary — a terminal rendering glitch, a scrolled-away window, a return from AFK. If the operator indicates they didn't see it ("no summary", "what notes?"), don't re-fire the picker first: re-send the summary as a plain message, then either re-ask or accept a plain-text answer in place of the picker. Losing the summary costs one re-send; a blind pick costs a wrong decision.

Keep the option order **stable across every firing of this picker** so the operator builds muscle memory and can pick without re-reading. This overrides the general `AskUserQuestion` convention of putting the recommended option first — this picker fires many times per PR, and shifting the layout per call costs more than the visual-primacy gain. Use this order:

1. **"Auto-handle all rounds"** — "Address these findings, push, and continue handling every subsequent review round the same way (without re-asking) until the PR is clean and ready to merge."
2. **"Address this round only"** — "Address these findings and push, but ask again before acting on the next review."
3. **Defer option** — label depends on review state, but always lives in slot 3:
   - APPROVED + findings → "Merge as-is" — "Take the approval and move on; leave findings unaddressed."
   - CHANGES_REQUESTED or COMMENTED + findings → "Leave PR sitting" — "Don't address; leave the PR open and I'll drive from here." (Merge isn't on the table when changes are formally requested.)

Tag the contextually-best default with **"(Recommended)"**. When a second option is in the same family as the recommended one — i.e. both pick the same overall direction (fix-now vs defer), trading off only in degree (auto-handle vs address-once trades picker-overhead for incremental control) — also tag the second one with **"(Recommended alternative)"**. The alternative tag is not "this is also fine"; it's "this is a sibling pick that some operators prefer, choose between them on personal preference." When the second option actively disagrees with the recommendation's direction, leave it untagged.

Default toward fixing inside the current PR — follow-up tracking overhead (issue, memory, future context reload) almost always exceeds the cost of one more commit on a PR that has the context loaded. Recommend the slot-3 defer option only when the findings are bikeshed-y or carry real rework risk (scope creep that would turn a tight PR into something needing its own review cycle, or changes outside the PR's stated scope).

Recommendation by state:

- **APPROVED + findings (worthwhile, not risky — the default case).** Recommended: option 1 ("Auto-handle all rounds"). Recommended alternative: option 2 ("Address this round only"). Option 3 untagged — defer-is-wrong when the fix is worth doing.
- **APPROVED + findings (bikeshed-y or risky).** Recommended: option 3 ("Merge as-is"). Options 1 and 2 untagged — both spend effort the recommendation says skip. This is the one case where the recommendation lives outside slot 1; trust the stable-order rule anyway.
- **CHANGES_REQUESTED or COMMENTED + findings.** Recommended: option 1 ("Auto-handle all rounds"). Recommended alternative: option 2 ("Address this round only"). Option 3 untagged — merge-as-is isn't on the table anyway, and "leave sitting" disagrees with the recommended direction.

Picking "Auto-handle all rounds" makes auto-handling sticky for the rest of this PR's life *within the current session*. The model has no per-PR memory across sessions, so if the session ends mid-cycle and a new one resumes, the picker re-fires on the next review — re-asking on a session boundary is the right call rather than silently auto-handling something the new session doesn't have full context for. Picking "Address this round only" still fixes + pushes + re-arms, but the picker fires again on the next review instead of acting silently. The third option (merge-as-is or leave-sitting) stops the workflow on this PR — no fix, no watch.

**Has findings, operator already opted in (picked "Auto-handle all rounds" earlier this session).** Don't re-ask. Address the findings, push the fix, re-arm the watch from its printed re-arm line with the new head, per `references/review-rounds.md`'s post-push rule, and repeat. Mention briefly what you addressed and that you're watching for the next review, but don't wait for the operator to approve each round — that's what the opt-in covered.

If at any point the operator says "stop" / "pause" / "let me drive", drop the auto-handling and revert to picker behavior for subsequent rounds.

## Responding to reviewers

Address comments to the reviewer using `@username` mentions.

**Put the answer where the next review will look**, and prefer the durable forms — **enforceable > prose > nothing**, applied to review:

1. **A test.** It proves the claim and fails loudly if it stops being true. Best answer to "are you sure this handles X?" by a wide margin.
2. **The code.** If the concern is real, the fix *is* the answer.
3. **The PR body.** For what you verified and how, what scope you checked, why one approach beat another. This is the as-built record, and the right home for evidence and provenance.

**Reply in the thread itself, and resolve it.** A top-level PR comment does not close a thread, and an unresolved thread is how a reviewer tracks outstanding work — so answering at the top level leaves the finding looking untouched no matter how thoroughly you fixed it. Use the `PRRT_…` id from the round packet's `── threads ──` section:

```bash
gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(
  input:{pullRequestReviewThreadId:$t,body:$b}){clientMutationId}}' -f t=<thread-id> -f b='<reply>'
"<skill-dir>/../../scripts/pr-threads.sh" <owner>/<repo> <n> --resolve <thread-id>
```

Resolve only what you actually addressed. A thread you are declining to act on stays open with your reasoning in it — that is a disagreement to surface, not a box to tick.

**A code comment is the last resort, and only when it would have earned its place anyway.** A reviewer's question is not a licence to add prose that fails the bar every comment has to clear: *will this still be true after the next change, and does it change what someone does?* An answer that exists only because someone asked once is transient state — if the only action a changing world requires is deleting the line, it was never a comment — and it will read as inexplicable defensiveness to the next person. If the answer is a *current, non-obvious constraint a future editor needs*, it was already worth a comment before the review; if it isn't, the PR body is where it goes.

When a finding you have already answered is re-raised, say so once and point at where the answer lives. Don't re-litigate it, and don't read the repetition as the answer having been rejected.
