# Git workflow: a review comes in

Part of the `git-workflow` skill. Read this when the review watch from
`references/review-rounds.md` reports a review. A clean review ends here with the
merge handoff; a review with findings continues in `references/review-findings.md`.

## When a review comes in

**Read the whole round in one call** — review bodies, inline findings, the standing verdict, and every unresolved thread. A verdict alone is a third of the review, and three separate reads are three chances to perform two.

**Run the `── next ──` command the watcher printed.** It is this, with every argument already filled in:

```bash
"<skill-dir>/../../scripts/pr-round.sh" <owner>/<repo> <n> <last-handled-sha> <since-iso> <your-login>
```

The same values the watcher was armed with — the SHA you last handled, the timestamp marking "handled up to here", and your own login, whose activity is excluded so your replies don't come back as news. It prints `── diff ──`, `── activity ──` and `── threads ──` sections, then one result line carrying `verdict`, `verdict_sha`, `at_head`, `reviewed_after_head` and a `_src` status per source. Pass `""` for the SHA when you have handled none yet; that asks for the full diff rather than a delta — which is what the printed command already does on a first round.

What the sections are for, and the mistake each one prevents:

- **`── activity ──`** — `"kind":"review"` is a review body, `"kind":"inline"` a finding filed on a line of the diff. Inline findings do **not** appear in `gh pr view --json reviews`, so a body reading "four things below" with three summary bullets is normal — the fourth, often the only real defect, is only ever inline. Each inline object carries an `id` — the REST comment id, which a reply via `in_reply_to` takes. It is **not** the `PRRT_…` thread id the GraphQL mutation in `references/review-findings.md`'s "Responding to reviewers" takes; that one is in `── threads ──`, and reaching for this `id` against that mutation costs a fetch to discover they are different namespaces.
- **`── threads ──`** — every unresolved thread, so you never work from memory about what you fixed: a reviewer reads open threads as outstanding work. Not narrowed to the bot's, because a human reviewer's thread blocks the merge just as surely.
- **The `_src` fields** — an empty section means "nothing there" only where its status reads `ok`. `fail` or `shape` means that source went blind, which is not a quiet round.

Read the review payload and pick one of three responses based on content: the clean case below, or one of the two findings cases in `references/review-findings.md`. Track whether the operator has opted in to auto-handling for *this* PR — once they pick "Auto-handle all rounds" in that file's picker, the choice is sticky across subsequent rounds until the PR merges or they explicitly stop.

**Clean review (APPROVED, no actionable findings).** The packet's `verdict=APPROVED at_head=1 reviewed_after_head=1` is what confirms it — those fields are `pr-verdict.sh`'s own answer, taken as part of the round, and the third is what keeps a force-push from re-anchoring a review onto a tree nobody read (see `SKILL.md`'s "Know the repo's merge settings"). **The watcher's `verdict=` is not, and must not stand in for them:** it reports what a poll saw, so an approval there may sit on a commit you have since pushed past, or have been superseded by a later `CHANGES_REQUESTED` from another reviewer. Where the repo doesn't dismiss stale approvals — the common case, since dismissal needs `required_approving_review_count` above 0 — the merge box shows an unqualified green check over exactly that state, so nothing on the PR will correct you. If the packet doesn't read `APPROVED` with both `at_head=1` and `reviewed_after_head=1`, this isn't the clean-review case: say what the standing verdict is and which SHA it sits on, and wait for the reviewer to re-verdict (which `reviewer` now does unprompted on any HEAD move — so this wait ends on its own and needs no prompting, `reviewed_after_head=unknown` excepted).

**Read the approving review's body before composing the handoff.** An approval is not always empty — reviewers put CI triage, deferred follow-ups and scope notes in it, and none of that reaches you as a finding. It is already in the packet, as the `"kind":"review"` object; skipping it means re-deriving from scratch what the reviewer has already written down, then reporting it as your own discovery.

With the verdict confirmed and that body read, tell the operator the PR is ready to merge, then **immediately re-arm the watch for the merge wait** from its `── re-arm ──` line (see `references/merge-wait.md`, which gives the wider window that stage needs) so the merge is caught whenever they trigger it — no round-trip if they merge right away, no unwatched gap if they step away first. Include the full URL (browser path) alongside the merge command (CLI path), framed as equals. Compose `<merge command>` per `references/merge.md` — hand over exactly one form, the one that will work:

> Reviewer approved at <commit>. No actionable findings. Ready to merge: <full URL>.
>
> ```
> <merge command>
> ```
>
> Or merge from the browser. I'm watching for the merge now — go ahead whenever you like, including hours from now, and I'll run post-merge cleanup automatically once it lands (and flag a conflict if one develops while checks run). If several hours pass with no merge, I'll check back once to remind you.

**Spawn the watcher — that edited re-arm line — before you send that message** — the "I'm watching for the merge now" line is a claim about a watcher that's actually running, so it must not go out on its own. If for any reason you don't spawn one (e.g. the PR is already merged by the time you'd report), drop that sentence and say what's actually true instead.

A "clean review" includes pure compliments and "noticed X looks good" observations. If you're unsure whether something is actionable, treat it as a finding (`references/review-findings.md`) rather than a no-op.
