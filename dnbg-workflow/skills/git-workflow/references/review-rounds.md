# Git workflow: review rounds

Part of the `git-workflow` skill. Read this when the operator sends the PR to
review, before spawning anything. `SKILL.md` carries the flow up to that point;
`references/merge.md` takes over once a review comes back clean.

## Watching for the first review

When the operator picks "Send to review" in `SKILL.md`'s picker, or otherwise signals the PR is ready (says "ready", "go", "mark it ready", etc.):

1. Run `gh pr ready <num> --repo <repo>` if the PR isn't already out of draft.
2. **Record the current head SHA.** Everything else the next arm needs comes back on the watch's own `── re-arm ──` line; this is a first arm, so there is nothing yet to carry.
3. **Spawn `watch-pr.sh`** as a **background** task (Bash `run_in_background: true`). It blocks until something happens, so its idle polling never enters the conversation, and the harness wakes you when it returns.

```bash
HEAD=$(gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid)
# A blank value means the `gh` call above failed. Catch it here rather than
# letting the watcher act on it.
[ -n "$HEAD" ] || { echo "could not resolve head SHA — re-run the watch"; exit 1; }
# --role=author is what makes this an author-side watch: it ignores your own
# login, does not wake on your own pushes, reports DIRTY and a terminal block
# because you own the merge, and sizes the window for a wait that should be
# short. The slug is derived from your own account, so it is not passed.
# --last-verdict= is empty here and only here: it says "no verdict handled yet".
"<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <num> \
  "$HEAD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "" --role=author --last-verdict=
```

**Re-arm from the line the watch prints, not from the clock.** Every result you
re-arm from is preceded by a `── re-arm ──` line carrying the next invocation
with `since` set to that run's own `now`. Reading the clock instead skips
whatever landed between the run returning and the next one starting, and
activity is counted against `since`, so what falls in that gap is filtered out
for good rather than deferred.

Both watchers trace themselves to `${TMPDIR:-/tmp}/dnbg-watch/<script>-<pid>.log` by default. When a watch returns no result line, that trace says which of three things happened: a `SIGNAL=` line (something stopped it), an `EXIT code=` line (it stopped itself), or a heartbeat and nothing after (an uncatchable kill). It is the only record — a killed watch writes no result, and the task output is empty either way.

**Do not hand-roll this loop.** It filters your own activity out, settles before reporting so a burst arrives whole, and polls on the SHA you last handled rather than current HEAD — a hand-written version gets each of these wrong in ways that surface as a review silently lost or a stale one reported as fresh. `tests/watch-pr.bats` pins them.

The script prints a summary of the activity it saw as one JSON object per line — who posted what kind of thing, where, without the text — then, on the results with a round behind them, a `── next ──` line carrying the `pr-round.sh` call that reads that round in full, then one result line. Treat the returns differently:

- **`result=ACTIVITY`** — a review, comment or reply landed. Go to "When a review comes in".
- **`result=COMMITS`** — someone pushed to the branch. If it wasn't you, read the change before responding to anything. **If `activity=1`, comments or replies landed in the same burst — handle them in this same pass**, per "When a review comes in". This is reachable from your side: a reviewer clicking "Update branch", or applying a suggestion while filing comments, produces exactly `COMMITS activity=1`. Ignoring the flag is *permanent* loss, not deferral — you re-arm with `since` set to now, so anything unread is filtered out for good.
- **`result=CLOSED`** — merged or closed. Stop watching; if `state=MERGED`, run the post-merge cleanup in `references/merge.md`.
- **`result=ERROR reason=<source>`** — the watch itself is broken: that source failed repeatedly, so it cannot see. **Do not re-arm** — you would poll straight back into the same failure. Check `gh auth status` and the `<num>`/`<repo>` pair, then tell the operator. Unlike `IDLE` this means nothing about the PR; the watch never got a look at it.
- **`result=ERROR reason=bad-args`** — the same code, the opposite remedy. Nothing failed: the watch refused to start because an argument could not do its job. Fix the argument and re-spawn; don't go near `gh auth status`. The guard on the spawn above catches the blank-`$ME` case before it gets here, so what actually reaches you is a re-arm's argument: an abbreviated `<last_head>` or `--last-verdict` value (see the note below — both take a full 40-character SHA), or a trailing flag that is neither `--was-draft` nor `--last-verdict=<sha>`.
- **`result=IDLE`** — the window elapsed with nothing. **Here this means something is probably wrong** — a reviewer that never replied, or the wrong `<num>`/`<repo>`. Wake once and tell the operator; do **not** silently re-arm. (The reviewer role treats `IDLE` as routine, which is why the role is an argument rather than a caller convention.)

  **Check whether HEAD is already approved before reporting that no review landed** — run `pr-verdict.sh` per `SKILL.md`'s "Know the repo's merge settings". If it is `APPROVED` at HEAD, the review is *in hand* and the watch simply missed it. Reporting "no review has landed" over a standing approval is a false statement about the PR, made from the watcher's blind spot rather than from the PR. If HEAD is not approved, the entry above stands.

- **`result=CHECKS checks=<names>`** — a check on the watched head stopped passing. Read it before telling the reviewer a finding is addressed: a round spent on a red build you pushed is a round nobody needed. Re-arm from the printed line, which carries the failure as handled so a standing one does not wake you again.
- **`result=DIRTY`** / **`result=BLOCKED cause=terminal`** — a conflict with base, or a block nothing pending will clear. Surface the cause and ask; don't resolve a conflict autonomously.

- **No `result=` line at all** — the task was killed or failed rather than returning. This is the dangerous one, because it looks exactly like a quiet watch while being its opposite: the watcher stopped observing, and anything pushed or posted since is unreported. **Never treat a missing result as "nothing happened."** Re-read `headRefOid` with `gh pr view` and compare against the SHA you last handled, then re-arm from what GitHub says rather than from what the watcher last told you. Traces make this diagnosable after the fact — see the trace note after the spawn block.

**A result line carrying `verdict_sha=<sha>` is the value to re-arm `--last-verdict` with.** It means the level-triggered check fired — a verdict stands at HEAD that you had not handled. No such field means it didn't fire, so carry the value you already had forward. Re-arming with an empty `--last-verdict=` after handling a verdict that is still at HEAD wakes the next watch instantly and repeatedly, since nothing about that verdict has changed.

The `verdict=<state>` beside it says which verdict that is, so you can tell a clean approval from a findings round before fetching anything. It is a branching hint only — the clean-review path below re-reads the verdict rather than trusting it.

The same spawn works after pushing a fix in response to feedback — record the new head and a fresh timestamp, and re-arm. After a push the old verdict is no longer at HEAD, so it can no longer trigger a wake whatever you pass.

⚠️ **The new head is the full 40-character SHA**, from `gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid` — never an abbreviated one you happened to print for a human. The watcher compares it as a string against what GitHub returns, so a short SHA can never match; it refuses one outright (`result=ERROR reason=bad-args`). This is the re-arm's exposure and the spawn's guard does not cover it: that guard tests `$HEAD` for *blankness*, and an abbreviated SHA is not blank. The same holds for `--last-verdict`, which is compared against `commit.oid` the same way — take it from the watcher's `verdict_sha` or from `pr-verdict.sh`, both of which report the full SHA.


## When a review comes in

**Read the whole round in one call** — review bodies, inline findings, the standing verdict, and every unresolved thread. A verdict alone is a third of the review, and three separate reads are three chances to perform two.

**Run the `── next ──` command the watcher printed.** It is this, with every argument already filled in:

```bash
"<skill-dir>/../../scripts/pr-round.sh" <owner>/<repo> <n> <last-handled-sha> <since-iso> <your-login>
```

The same values you armed the watcher with — the SHA you last handled, the timestamp marking "handled up to here", and your own login, whose activity is excluded so your replies don't come back as news. It prints `── diff ──`, `── activity ──` and `── threads ──` sections, then one result line carrying `verdict`, `verdict_sha`, `at_head`, `reviewed_after_head` and a `_src` status per source. Pass `""` for the SHA when you have handled none yet; that asks for the full diff rather than a delta — which is what the printed command already does on a first round.

What the sections are for, and the mistake each one prevents:

- **`── activity ──`** — `"kind":"review"` is a review body, `"kind":"inline"` a finding filed on a line of the diff. Inline findings do **not** appear in `gh pr view --json reviews`, so a body reading "four things below" with three summary bullets is normal — the fourth, often the only real defect, is only ever inline. Each inline object carries an `id` — the REST comment id, which a reply via `in_reply_to` takes. It is **not** the `PRRT_…` thread id the GraphQL mutation under "Responding to reviewers" takes; that one is in `── threads ──`, and reaching for this `id` against that mutation costs a fetch to discover they are different namespaces.
- **`── threads ──`** — every unresolved thread, so you never work from memory about what you fixed: a reviewer reads open threads as outstanding work. Not narrowed to the bot's, because a human reviewer's thread blocks the merge just as surely.
- **The `_src` fields** — an empty section means "nothing there" only where its status reads `ok`. `fail` or `shape` means that source went blind, which is not a quiet round.

Read the review payload and pick one of three responses based on content. Track whether the operator has opted in to auto-handling for *this* PR — once they pick "Auto-handle all rounds" in the picker below, the choice is sticky across subsequent rounds until the PR merges or they explicitly stop.

**Clean review (APPROVED, no actionable findings).** The packet's `verdict=APPROVED at_head=1 reviewed_after_head=1` is what confirms it — those fields are `pr-verdict.sh`'s own answer, taken as part of the round, and the third is what keeps a force-push from re-anchoring a review onto a tree nobody read (see `SKILL.md`'s "Know the repo's merge settings"). **The watcher's `verdict=` is not, and must not stand in for them:** it reports what a poll saw, so an approval there may sit on a commit you have since pushed past, or have been superseded by a later `CHANGES_REQUESTED` from another reviewer. Where the repo doesn't dismiss stale approvals — the common case, since dismissal needs `required_approving_review_count` above 0 — the merge box shows an unqualified green check over exactly that state, so nothing on the PR will correct you. If the packet doesn't read `APPROVED` with both `at_head=1` and `reviewed_after_head=1`, this isn't the clean-review case: say what the standing verdict is and which SHA it sits on, and wait for the reviewer to re-verdict (which `reviewer` now does unprompted on any HEAD move — so this wait ends on its own and needs no prompting, `reviewed_after_head=unknown` excepted).

**Read the approving review's body before composing the handoff.** An approval is not always empty — reviewers put CI triage, deferred follow-ups and scope notes in it, and none of that reaches you as a finding. It is already in the packet, as the `"kind":"review"` object; skipping it means re-deriving from scratch what the reviewer has already written down, then reporting it as your own discovery.

With the verdict confirmed and that body read, tell the operator the PR is ready to merge, then **immediately spawn the merge watcher** (see `references/merge.md` → start it proactively) so the merge is caught whenever they trigger it — no round-trip if they merge right away, no unwatched gap if they step away first. Include the full URL (browser path) alongside the merge command (CLI path), framed as equals. Compose `<merge command>` per `references/merge.md` — hand over exactly one form, the one that will work:

> Reviewer approved at <commit>. No actionable findings. Ready to merge: <full URL>.
>
> ```
> <merge command>
> ```
>
> Or merge from the browser. I'm watching for the merge now — go ahead whenever you like, including hours from now, and I'll run post-merge cleanup automatically once it lands (and flag a conflict if one develops while checks run). If several hours pass with no merge, I'll check back once to remind you.

**Spawn the watcher before you send that message** — the "I'm watching for the merge now" line is a claim about a watcher that's actually running, so it must not go out on its own. If for any reason you don't spawn one (e.g. the PR is already merged by the time you'd report), drop that sentence and say what's actually true instead.

A "clean review" includes pure compliments and "noticed X looks good" observations. If you're unsure whether something is actionable, treat it as a finding (next case) rather than a no-op.

**Has findings, no sticky opt-in yet.** Post a summary of the review as a normal message, **then** call `AskUserQuestion` with three options (the tool auto-appends "Other" for anything else). The summary is the evidence the choice is made on — the operator decides fix-now vs defer from what you show them, usually without opening the review. A picker with no summary in front of it forces them to either pick blind or go read the review on GitHub themselves, which defeats the point of you driving the cycle.

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

Picking "Auto-handle all rounds" makes auto-handling sticky for the rest of this PR's life *within the current session*. The model has no per-PR memory across sessions, so if the session ends mid-cycle and a new one resumes, the picker re-fires on the next review — re-asking on a session boundary is the right call rather than silently auto-handling something the new session doesn't have full context for. Picking "Address this round only" still fixes + pushes + spawns a fresh poll, but the picker fires again on the next review instead of acting silently. The third option (merge-as-is or leave-sitting) stops the workflow on this PR — no fix, no poll.

**Has findings, operator already opted in (picked "Auto-handle all rounds" earlier this session).** Don't re-ask. Address the findings, push the fix, spawn a fresh background poll for the next review on the new head SHA, and repeat. Mention briefly what you addressed and that you're watching for the next review, but don't wait for the operator to approve each round — that's what the opt-in covered.

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

