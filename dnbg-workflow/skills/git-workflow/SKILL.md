---
name: git-workflow
description: How to change any tracked file in a covered repo — git worktree creation (and treating other sessions' worktrees as expected rather than reportable), PR opening (drafts by default), pairing PRs across repos for multi-repo changes, watching for reviews, responding to reviewers, and post-merge cleanup. Load this whenever you're about to edit, write, or modify any tracked file in a covered repo (application code, skills, plugins, docs, configs, tests — anything that would show up in `git status`), open a PR, mark a PR ready, watch for review feedback, address review feedback, or clean up after a merge. The trigger is a tracked file changing, not the user's choice of words.
---

# Git workflow

This is the standard flow for any code change in a covered repo — one whose
`origin` belongs to an account in this plugin's `owners` setting. Never modify
the main checkout directly; always work in a worktree.

## Starting a change

**If this work originates from an existing issue** (the task named an issue number or URL), load `issue-workflow` and claim the issue *before* the steps below — claiming and the freshness probe come before the worktree, not after. Don't let "the work ends in file edits" pull you straight here; issue pickup is the entry action, this flow is just the destination.

1. `git fetch origin` — fetches all refs so later diffs against other branches don't surprise you with stale data.
2. `gh pr list --repo <repo> --state open` — if any open PR might touch the files you're about to change, check its diff (`gh pr diff <num>`) and either coordinate or hold off. Independent staleness check from the fetch above: that one catches a stale base, this one catches concurrent work — without it, two PRs against the same node in the same file can both rebase cleanly and one becomes a wasted no-op the moment the other merges.
3. Re-read any files you touched in a prior session — code may have changed.
4. `git worktree add .worktrees/<branch-name> -b <branch-name> origin/<default-branch>` — the default branch comes from the settings read below; don't assume `main`. If the change spans repos, the branch name is the pairing key; see "Multi-repo changes" below before picking it.
5. Make changes in the worktree.
6. Commit, push, and **open the PR as a draft** (`gh pr create --draft ...`).
7. After each commit, update the PR description if needed so it reflects the **as-built** state, written per **"Writing the PR description"** below — we do not narrate the development history in the description.
8. **Announce the PR and call `AskUserQuestion`** to ask whether to send it to review — see "After opening a draft PR" below for the exact two-option picker. Do **not** mark it ready yourself, and do **not** substitute a prose question for the picker: drafting keeps reviewers (human and bot) from spending attention on something the author hasn't endorsed yet, and the picker is what makes send-to-review a single keypress.
9. When the operator picks "Send to review" (or later says "ready" / "go"), mark it ready (`gh pr ready <number> --repo <repo>`) and start watching for the first review — see "Watching for the first review" below.
10. Never merge. Only a human merges PRs.

Worktrees live in `.worktrees/` inside the repo. Ensure `.worktrees` is in `.gitignore`.

**Concurrent work is the norm — other worktrees are not a finding.** `.worktrees/` routinely holds branches from other sessions, other agents, and the operator's own in-flight work. Their presence is expected, needs no report, and is not evidence anything is wrong. Never touch one you didn't create.

What *is* worth raising is a concrete collision: step 2's open-PR check, or a sibling worktree, shows work landing on the same files or the same design surface as yours. Flag that with the specific overlap — "`<branch>` also edits `src/auth.ts:40-70`" — so the operator can decide whether to coordinate. The signal is the conflict, not the parallelism.

## Know the repo's merge settings

Three later steps depend on how this particular repo is configured: which branch to fork from, how the merge command is composed, whether a push dismisses an approval, and what the post-merge cleanup still has to do. **Read them, don't assume them** — these settings vary between an org's repos and a personal account's, and between two repos in the same account.

Read once per repo, early:

```bash
gh api repos/<owner>/<repo> --jq \
  '{default_branch, allow_auto_merge, allow_squash_merge, allow_merge_commit,
    allow_rebase_merge, delete_branch_on_merge}'
```

| Field | What it decides |
| --- | --- |
| `default_branch` | what you branch from and target — not necessarily `main` |
| `allow_auto_merge` | whether `gh pr merge --auto` works at all |
| `allow_squash_merge` / `allow_merge_commit` / `allow_rebase_merge` | which merge flag to hand the operator, and whether the branch tip ends up an ancestor of the base (which decides `-d` vs `-D` locally) |
| `delete_branch_on_merge` | whether the remote branch still needs deleting after the merge |

**Don't read branch protection to find out whether an approval still counts.** Reaching for the repo's `dismiss_stale_reviews` flag is wrong twice over. That flag lives on the branch-protection endpoint, which requires **admin** — so on a repo where you have only write access (common when contributing to an org repo you don't administer) it answers 403 or 404 and tells you nothing. And where it *does* answer, the answer misleads: `dismiss_stale_reviews: true` alongside `required_approving_review_count: 0` means no approval is required, so there is no approval gate to make stale and nothing is ever dismissed. That pairing is the default on a personal repo that gates on CI, and it is what two sessions running two different skills tripped over: each read `true` off that flag, concluded a pushed-past approval was gone, and reported a PR as needing another review when nothing had been dismissed.

The question that field gets reached for is always really **"is HEAD approved?"**. Where approvals are *required* — `reviewDecision` is non-null — that field answers it directly and is the primary source: it accounts for supersession and for multiple required reviewers, neither of which the check below models. Where they are not required, `reviewDecision` is `null` and says nothing, and this is what remains:

```bash
gh pr view <num> --repo <repo> --json headRefOid,reviews --jq \
  '{head: .headRefOid,
    last_verdict: ([.reviews[]
      | select(.state=="APPROVED" or .state=="CHANGES_REQUESTED" or .state=="DISMISSED")]
      | last)}'
```

HEAD is approved **iff** `last_verdict.state == "APPROVED"` and `last_verdict.commit.oid == head`. Both halves are load-bearing:

- **The latest verdict, not the latest approval.** Filtering to `APPROVED` and taking the last one reads an `APPROVED` followed by a `CHANGES_REQUESTED` at the *same* SHA as approved. Two routes reach that: a second reviewer objecting over a standing approval, and a reviewer reversing itself after a reply. Where `reviewDecision` is `null` nothing downstream catches it.
- **`COMMENTED` is not a verdict** and must stay out of the set — a reviewer answering a thread posts one, and counting it would blank the verdict on every exchange.

An approval further down the list is an approval of a diff nobody is merging. Use this wherever the answer matters — before telling the operator a PR is ready to merge, and before merging one yourself if you ever have cause to.

For a multi-repo change, read this **per repo**. Siblings genuinely differ, and a setting borrowed from the wrong one produces a merge command that fails or a cleanup step that silently does nothing.

## Writing the PR description

The description reflects the **as-built** state (step 7) — and every claim in it must be *true and earned*. A reviewer who catches one inflated claim discounts the whole description, so the asymmetry is stark: under-claiming costs nothing, over-claiming costs trust.

- **Name what you verified, and how — don't imply more.** "Typechecks (`tsc`)" and "CI green" are not "tested"; "eyeballed one case on dev" is not "verified end-to-end." State the check you actually ran; if you didn't run one, don't phrase the body so it reads as if you did.
- **Don't assert coverage you don't have.** No unit runner for a file? Say its helpers are covered by typecheck + manual, not that they're "tested." Never describe intended or aspirational tests as existing ones.
- **Don't state impact without evidence.** Performance, cost, "fixes X for all inputs" — back it with the measurement or the reasoning, or hedge it. A confident-sounding number with no source is an over-claim.
- **Claim only the scope you checked.** The over-claim usually starts one step earlier, as an unexamined assumption written up as fact: that a change generalizes, that it fixes the root cause (not just the symptom you reproduced), that the correlation you saw is the cause, that nothing else is affected. Verify the assumption, or state the scope you actually verified ("fixes the observed case; other inputs unchecked"; "removes the symptom — root cause not confirmed"). An assumption is not a result.
- **Surface gaps, not just wins.** Known limitations, unverified branches, and deferred follow-ups belong in the body — these are as-built facts about the result, not the development narrative step 7 rules out; omitting them reads as "all handled," and the next reader inherits the surprise.

`issue-workflow` holds issue bodies to the same bar, and states it there. When unsure whether a claim is earned, weaken it or cut it — a description a reviewer can trust line-for-line is worth more than an impressive one they have to second-guess.

## Multi-repo changes

When one logical change spans repos (e.g. an infrastructure change plus the application change it enables), pair the PRs so a list view shows what goes with what:

1. **Same branch name in every repo.** Pick the branch name once and reuse it verbatim for each repo's worktree. It's the join key: it exists before any PR does (no ordering problem), it shows in `gh pr list`, and `gh search prs --owner <owner> head:<branch-name>` returns the whole set.
2. **Shared title tag.** Prefix every sibling PR's title with the branch name in brackets — `[<branch-name>] <title>`. github.com's PR list doesn't show branch names, so the tag is what makes the pairing visible there. The tag *is* the branch name, not a separate slug — one join key, derivable in both directions.

3. **Every sibling references the issue by full URL; exactly one closes it.** When the set resolves an issue, put the issue URL in *each* PR's body — the sibling's opening line is a good home ("The infrastructure half of `<issue URL>`"). Only the PR that actually completes the work carries a closing keyword (`Closes <issue URL>`); the others just mention it.

   This is not bookkeeping. A mention is the **only** thing that makes a sibling discoverable from the issue: `closedByPullRequestsReferences` returns just the closing PR, and both of the other routes — the issue timeline's `cross-referenced` events, and text search — are driven by the mention. A sibling whose body never names the issue cannot be found from the issue by any means, so anyone working from it (the `reviewer` skill's issue-scoped mode, or a human) sees a set that looks complete and is not. The failure is silent, and it lands on whoever reviews or ships the half that did get linked.

   The branch name pairs the PRs *to each other*; the issue URL is what ties the set *to the issue*. Both are needed — neither substitutes for the other.

Single-repo PRs (the common case) stay untagged — the tag's presence is itself the signal that siblings exist in other repos.

If a change turns multi-repo midway — the first PR is already open when you discover a second repo needs to change — reuse its branch name for the new worktree and retitle the open PR to add the tag (`gh pr edit <num> --repo <repo> --title "..."`) when you open the sibling.

## After opening a draft PR

**Before this picker, if you made a substantive design change mid-implementation** — a departure from the approach agreed at pickup (the issue's "Proposed approach", or, for a PR with no issue, whatever you and the operator settled on in chat), a contract/interface change, anything a reviewer would be surprised by — surface that change and its rationale in chat *first*, per `issue-workflow`'s "Surface design changes that emerge mid-implementation". Send-to-review is the gate it's tied to: the operator must learn the design moved before review and manual testing run against it, not discover it inside the review. The rule's home is `issue-workflow`, but it applies to any PR — without an issue, the "agreed design" simply lives in the chat thread instead of an issue body.

Announce the draft PR with its full URL, then call `AskUserQuestion` with two options (the tool auto-appends "Other" for anything else):

1. **"Send to review (Recommended)"** — "Mark the PR ready and watch for the first review."
2. **"Not yet"** — "Leave it in draft; say 'ready' whenever you want it reviewed."

The picker makes the default path (send to review) a single keypress while keeping the out visible. On "Send to review", run the "Watching for the first review" flow below. On "Not yet", leave the PR in draft and carry on — the operator saying "ready" later re-enters the same flow.

Don't offer "or run `gh pr ready` yourself" as an option or alternative. The auto-poll and the review-handling logic only fire when you do the mark-ready step, so an operator who marks it ready out-of-band gets no follow-up from you — which means the dual-path framing misleads them about what to expect. If they want to drive the review cycle manually, they can do so without your prompting; the skill's job is to make the auto-handling path the clear default.

## Watching for the first review

When the operator picks "Send to review" in the picker above, or otherwise signals the PR is ready (says "ready", "go", "mark it ready", etc.):

1. Run `gh pr ready <num> --repo <repo>` if the PR isn't already out of draft.
2. **Record state**: the current head SHA, and a timestamp marking "handled up to here".
3. **Spawn `watch-pr.sh`** as a **background** task (Bash `run_in_background: true`). It blocks until something happens, so its idle polling never enters the conversation, and the harness wakes you when it returns.

```bash
HEAD=$(gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid)
ME=$(gh api user --jq .login)
# Both are load-bearing arguments and the script fails *quietly* on either being
# blank: an empty head means its commit check can never fire for the whole
# window, and an empty login makes its exclude-filter match nobody — so your own
# thread replies would register as activity, which is the exact failure the
# fifth argument exists to prevent. Bail loudly instead.
[ -n "$HEAD" ] && [ -n "$ME" ] || { echo "could not resolve head SHA / login — re-run the watch"; exit 1; }
# WINDOW=1800 overrides the script's 6h default. That default is right for
# `reviewer`, where IDLE is routine; here IDLE means something is wrong, and a
# signal the operator waits six hours for is not a signal. A bot reviewer
# normally replies in 1–3 minutes, so 30 minutes is a generous safety net.
WINDOW=1800 "<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <num> \
  "$HEAD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ME"
```

The path reaches out of this skill's directory on purpose: the script is shared with `reviewer`, which watches the same PRs from the other side. `CLAUDE_PLUGIN_ROOT` is exported to *hook* processes, not to yours, so a skill can only address a sibling relative to its own announced Base directory — and skill directories are always `<plugin>/skills/<name>/`, which makes `../../scripts/` deterministic.

**Do not hand-roll this loop.** An earlier version of this skill inlined it here, and the inline version was wrong in ways that are not obvious until they bite:

- It polled for a review **on the current head SHA**. That is right after you push a fix, and wrong after you answer a reviewer in threads — replying moves nothing, so the filter matches the review you already handled and wakes you with stale news dressed as a fresh verdict.
- The fifth argument is the login whose activity to **ignore** — your own. This is load-bearing, not padding: replying to a review thread registers as a *review event authored by you*, with an empty body and state `COMMENTED`, so without it your own reply satisfies the wait and reports a PR as reviewed when nobody has looked. The script also handles the two spellings GitHub uses for the same bot (`<slug>` via GraphQL, `<slug>[bot]` via REST), which a hand-written filter reliably gets wrong.
- It returned on the first thing it saw. A round is a **burst** — a reviewer files a verdict and several inline comments — and returning early is *lossy* rather than merely mis-ordered, because you re-arm with `since` set to now and anything unread is filtered out permanently. The script settles before reporting.

Being a file rather than a fenced block is itself part of the fix: `shellcheck` covers `scripts/`, and covers nothing inside a `.md`.

The script prints one result line. Treat the returns differently:

- **`result=ACTIVITY`** — a review, comment or reply landed. Go to "When a review comes in".
- **`result=COMMITS`** — someone pushed to the branch. If it wasn't you, read the change before responding to anything. **If `activity=1`, comments or replies landed in the same burst — handle them in this same pass**, per "When a review comes in". This is reachable from your side: a reviewer clicking "Update branch", or applying a suggestion while filing comments, produces exactly `COMMITS activity=1`. Ignoring the flag is *permanent* loss, not deferral — you re-arm with `since` set to now, so anything unread is filtered out for good. Same failure the third bullet above gives as a reason not to hand-roll this.
- **`result=CLOSED`** — merged or closed. Stop watching; if `state=MERGED`, run the post-merge cleanup.
- **`result=ERROR reason=<source>`** — the watch itself is broken: that source failed repeatedly, so it cannot see. **Do not re-arm** — you would poll straight back into the same failure. Check `gh auth status` and the `<num>`/`<repo>` pair, then tell the operator. Unlike `IDLE` this means nothing about the PR; the watch never got a look at it.
- **`result=IDLE`** — the window elapsed with nothing. **Here this means something is probably wrong** — a reviewer that never replied, or the wrong `<num>`/`<repo>`. Wake once and tell the operator; do **not** silently re-arm. (`reviewer` treats `IDLE` as routine and re-arms, because a quiet PR is expected on that side. Same script, opposite caller.)

  **Check whether HEAD is already approved before reporting that no review landed** — run the `last_verdict` check from "Know the repo's merge settings". If it is `APPROVED` at HEAD, the review is *in hand* and the watch simply missed it: it was armed with a `since` past the review, or the verdict landed in the gap between the last poll and the spawn. Reporting "no review has landed" there is a false statement about the PR, made from the watcher's blind spot rather than from the PR. If HEAD is not approved, the entry above stands and the reviewer really is the thing to check.

The same spawn works after pushing a fix in response to feedback — record the new head and a fresh timestamp, and re-arm.


## When a review comes in

**Fetch the inline comments first — the review body is not the whole review.** Findings are routinely filed on lines of the diff, and those do **not** appear in `gh pr view --json reviews`. Read them before summarizing anything:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/comments --paginate \
  --jq '.[] | "── \(.path):\(.line // .original_line)\n\(.body)\n"'
```

This is not belt-and-braces. A body reading "four things below" with three summary bullets is normal — the fourth, often the only real defect, is inline. Summarize from the body alone and the next round opens with every finding still outstanding, because none of them was ever addressed.

**And enumerate the unresolved threads — don't trust your own list of what you fixed.** This one has a command because prose was not enough: it was stated here without one, and was skipped twice in a single PR, with three threads left open while rounds were reported as handled. The reviewer read open threads as outstanding work, which is exactly what they mean.

```bash
gh api graphql -f query='{repository(owner:"<owner>",name:"<repo>"){pullRequest(number:<n>){
  reviewThreads(first:50){nodes{id isResolved path line comments(first:1){nodes{body}}}}}}}' \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)]'
```

Run all three — verdict, inline comments, threads — before summarizing anything. A verdict alone is a third of the review.

Read the review payload and pick one of three responses based on content. Track whether the operator has opted in to auto-handling for *this* PR — once they pick "Auto-handle all rounds" in the picker below, the choice is sticky across subsequent rounds until the PR merges or they explicitly stop.

**Clean review (APPROVED, no actionable findings).** First, **confirm the standing verdict is an approval attached to the current HEAD** — run the `last_verdict` check from "Know the repo's merge settings". `APPROVED` in the watcher payload only tells you an approval exists somewhere in the list; it may sit on a commit you have since pushed past, or have been superseded by a later `CHANGES_REQUESTED` from another reviewer. Where the repo doesn't dismiss stale approvals — the common case, since dismissal needs `required_approving_review_count` above 0 — the merge box shows an unqualified green check over exactly that state, so nothing on the PR will correct you. If the last verdict isn't `APPROVED` at HEAD, this isn't the clean-review case: say what the standing verdict is and which SHA it sits on, and wait for the reviewer to re-verdict (which `reviewer` now does unprompted on any HEAD move).

Once they match, tell the operator the PR is ready to merge, then **immediately spawn the merge watcher** (see "Watching for the merge to complete" → start it proactively) so the merge is caught whenever they trigger it — no round-trip if they merge right away, no unwatched gap if they step away first. Include the full URL (browser path) alongside the merge command (CLI path), framed as equals. Compose `<merge command>` per "Composing the merge command" below — hand over exactly one form, the one that will work:

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

**Reply in the thread itself, and resolve it.** A top-level PR comment does not close a thread, and an unresolved thread is how a reviewer tracks outstanding work — so answering at the top level leaves the finding looking untouched no matter how thoroughly you fixed it. Use the thread `id` from the enumeration above:

```bash
gh api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(
  input:{pullRequestReviewThreadId:$t,body:$b}){clientMutationId}}' -f t=<thread-id> -f b='<reply>'
gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -f t=<thread-id>
```

Resolve only what you actually addressed. A thread you are declining to act on stays open with your reasoning in it — that is a disagreement to surface, not a box to tick.

⚠️ **A code comment is the last resort, and only when it would have earned its place anyway.** A reviewer's question is not a licence to add prose that fails the bar every comment has to clear: *will this still be true after the next change, and does it change what someone does?* An answer that exists only because someone asked once is transient state — if the only action a changing world requires is deleting the line, it was never a comment — and it will read as inexplicable defensiveness to the next person. If the answer is a *current, non-obvious constraint a future editor needs*, it was already worth a comment before the review; if it isn't, the PR body is where it goes.

When a finding you have already answered is re-raised, say so once and point at where the answer lives. Don't re-litigate it, and don't read the repetition as the answer having been rejected.

## Issue and PR references

Full GitHub URLs, always — per the always-on rule "Reference issues and PRs by full URL". The rationale and the memory-file exception live there.

## Composing the merge command

Whenever you hand the operator a merge command, emit exactly one form — the right one for the observed state. (That's the immediately-runnable one in every case but the no-auto-merge-with-pending-checks branch below, where no immediately-runnable form exists and the handoff says so.) A clean review does not mean the PR is mergeable *right now*: a review on a fresh push usually lands while required checks are still re-running, and a plain `gh pr merge` is refused until they pass. Don't present `--auto` as an optional garnish ("add `--auto` if you want it to wait...") — you have the data to decide, so deciding is your job, not the operator's.

Two inputs. The **repo settings** — `allow_auto_merge` and which merge methods are enabled — come from "Know the repo's merge settings" above. The **live merge state** has to be read now:

```bash
gh pr view <num> --repo <repo> --json mergeStateStatus,statusCheckRollup
```

Pick the merge-method flag from what the repo actually allows (`--squash`, `--merge`, or `--rebase`); if several are enabled, prefer the repo's own convention, and `--squash` when there's no signal. Then pick the form by state:

- **`mergeStateStatus=CLEAN`** (or `UNSTABLE` — only non-required checks failing) — plain form: `gh pr merge <num> --repo <repo> <method> --delete-branch`.
- **`BLOCKED`, required checks still running, `allow_auto_merge=true`** — auto form: `gh pr merge <num> --repo <repo> <method> --delete-branch --auto`. The plain form would be refused right now; `--auto` queues the merge to fire when checks pass.
- **`BLOCKED`, required checks still running, `allow_auto_merge=false`** — both forms are refused right now (`--auto` needs the repo setting). Give the plain form, but say explicitly that required checks are still running and the command will work once they're green — the browser merge button enables at the same moment.
- **`BLOCKED`, no checks pending** — the PR is not actually mergeable (failed required check, dismissed approval, branch behind base). Don't send a ready-to-merge handoff at all; surface the cause and ask.

Drop `--delete-branch` when `delete_branch_on_merge` is already on for the repo — it's redundant there, though harmless.

For a multi-repo PR set (see "Multi-repo changes"), run both reads **per repo** — siblings can need different forms, because both the check state and the repo settings differ across repos.

**Formatting:** put each merge command on its own line in a fenced code block, never inline in a sentence or bullet — inline commands can't be cleanly triple-click-selected or copy-pasted. For a multi-PR handoff, one block with one command per line:

```
gh pr merge 247 --repo <owner>/infrastructure --squash --delete-branch --auto
gh pr merge 48 --repo <owner>/examples --squash --delete-branch
```

(Don't column-align the commands with padding spaces — extra whitespace inside a command is harmless but looks like it might not be.)

## Watching for the merge to complete

**Start it proactively.** The moment a review comes back clean (the clean-review handoff above), spawn the background poller below on the PR — don't wait for the operator to announce anything. It watches until the PR merges, closes, hits a conflict, hits a terminal block, or its deadline elapses, then wakes you once. This removes the round-trip in the common case (operator merges right away) and the unwatched gap in the AFK case (operator merges hours later). Spawning a watcher is read-only — it never merges; only a human does.

**One watcher per PR.** A proactive watcher is normally already in flight by the time the operator says anything about the merge. Don't spawn a second — verify state as below and let the running one carry it to completion.

Any time the operator says something about the merge — kicking it off ("merging", "auto-merge is on", "go ahead") **or asserting it's done** ("merged", "it's merged", "done", "all set") — **verify state with `gh pr view` before acting on the words**. Operators use "merged" for both "the merge button was clicked, auto-merge is queued" and "GitHub shows merged"; same phrasing, different states. Trusting the words can mean premature cleanup or a duplicate watcher.

```bash
gh pr view <num> --repo <repo> --json state,mergeStateStatus,autoMergeRequest
```

Branch on the response:

- **`state=MERGED`** — operator's claim is accurate. Run the post-merge cleanup below. (If a proactive watcher is still in flight, it will report `MERGED` shortly too — ignore the duplicate notification rather than running cleanup twice.)
- **`state=CLOSED`** (without merge) — closed unmerged. Acknowledge, stop the workflow, leave the worktree alone in case they reopen.
- **`state=OPEN`, `mergeStateStatus=DIRTY`** — a conflict already exists at verify time. Don't spawn the poller; surface the URL and the cause and ask how to proceed.
- **`state=OPEN`, `autoMergeRequest` non-null** — auto-merge is scheduled. If a proactive watcher is already running for this PR (the usual case after a clean review), just say "auto-merge is pending — the watcher will catch it" and let it run; otherwise spawn the background poller below. This applies even if `mergeStateStatus=BLOCKED`: a required check still running shows as BLOCKED until it completes, and the poller disambiguates transient block (some required check still in progress) from terminal block (all checks done with a required one failed).
- **`state=OPEN`, `autoMergeRequest` null, `mergeStateStatus=BLOCKED`** — auto-merge isn't scheduled and branch protection is blocking the merge. Don't spawn the poller; surface and ask. (Distinct from the previous case: without auto-merge enabled, a BLOCKED state needs a human to either fix the block or enable auto-merge.)
- **`state=OPEN`, `autoMergeRequest` null** — nothing scheduled. Either the operator was being forward-looking ("I'm about to merge") or thought it had merged when it hadn't. Don't spawn a second watcher; if a proactive one is already running, say so ("not merged yet — I'm still watching") and otherwise ask before assuming.

### Background poller

Spawn this as a **background** poller (Bash `run_in_background: true`) — both for the proactive watch right after a clean review (state `OPEN`, nothing scheduled yet) and whenever a verify branch above says to spawn. Background for the same reason the review watcher is: running it in the foreground replays the `gh pr view` command and every empty intermediate result into context, once per loop iteration. The deadline below is measured from **when you spawn the poller**, not from PR creation or the review — so a verify-branch spawn hours later (e.g. the operator pings on return after the proactive watcher's session ended) still gets a full window.

```bash
# Deadline: several hours, so an operator who merges later in the day is still
# caught. We never silently re-arm (on timeout we wake and remind, once), so the
# deadline only sets *when to remind*, not how often we wake — make it generous.
# Exactly one wake either way: on the merge, or once on timeout.
deadline=$(( $(date +%s) + 21600 ))   # 6h
until
  # Only the gh call is silenced. Its failures are the transient ones, and their
  # stderr would otherwise survive into the background task's result, making a
  # watch that rode out a blip and then reported MERGED read like one that died.
  # The jq calls below are deliberately NOT silenced: a jq failure here means the
  # payload shape changed, which is never transient and must stay visible.
  RAW=$(gh pr view <num> --repo <repo> --json state,mergeStateStatus,statusCheckRollup,reviewDecision 2>/dev/null)
  # Update state only from a poll that actually succeeded, and record that at
  # least one did. Overwriting unconditionally would let a single blip on the tick
  # that happens to observe the deadline erase six healthy hours — the run would
  # lose `result=TIMEOUT` (the STATE test below short-circuits on empty) and the
  # operator would never be reminded the PR is still open.
  if [ -n "$RAW" ]; then
    reached=1
    J=$RAW
    STATE=$(echo "$J" | jq -r .state)
    MSS=$(echo "$J" | jq -r .mergeStateStatus)
    # PENDING counts checks that haven't reached a terminal state. CheckRun
    # entries use .status (COMPLETED is terminal); StatusContext entries use
    # .state (PENDING is non-terminal). Any non-terminal check means BLOCKED
    # is still transient.
    #
    # `// []` because statusCheckRollup is null on a PR with no checks at all,
    # and iterating null is a hard jq error — which would leave PENDING empty for
    # the rest of the window and silently disable the terminal-BLOCKED test
    # below, so a failed required check would sit unreported until the deadline.
    PENDING=$(echo "$J" | jq -r '[(.statusCheckRollup // [])[] | select((.status != null and .status != "COMPLETED") or .state == "PENDING")] | length')
  fi
  [ "$STATE" = MERGED ] || [ "$STATE" = CLOSED ] || [ "$MSS" = DIRTY ] \
    || { [ "$MSS" = BLOCKED ] && [ "$PENDING" = "0" ]; } \
    || [ "$(date +%s)" -ge "$deadline" ]
do
  sleep 60
done
# Not a single poll succeeded across the whole window — keyed on the flag, not on
# `$STATE`, because the last poll failing is not the same event as every poll
# failing. Silencing gh above removed the stderr that used to hint at this, so
# without the flag a blank result is indistinguishable from a bug in the loop.
[ -n "${reached:-}" ] || echo "result=UNREACHABLE"
# Plain deadline timeout (still mergeable, just no merge yet) vs a real terminal
# state — distinguish so the return-branch can tell "remind the operator" from
# "surface a problem".
[ "$STATE" = OPEN ] && [ "$MSS" != DIRTY ] && ! { [ "$MSS" = BLOCKED ] && [ "$PENDING" = "0" ]; } \
  && [ "$(date +%s)" -ge "$deadline" ] && echo "result=TIMEOUT"
echo "state=$STATE mergeStateStatus=$MSS pending_checks=$PENDING"
echo "$J"
```

`reviewDecision` is included so the surface-and-ask branch below can identify a dismissed-approval cause from the same JSON the poller already returned — no extra `gh pr view` call. Read it as a *gate* question, not an approval question: `null` means no review is required to merge on this repo, which rules review out as the cause of a `BLOCKED`. It says nothing about whether HEAD is approved — that is the `commit.oid` comparison, and on a repo with `reviewDecision: null` it is the only thing that answers it.

Sleep 60s, rather than the 30s the shared review watcher polls at by default — match the interval to how fast the watched thing moves (merges take minutes-to-hours; reviews land in 1–3 min), *not* to cost. The loop's intermediate iterations run in the background and never enter the conversation, so poll frequency costs no tokens — only GitHub API calls. The token cost is the single model wake when the loop exits, and that's set by the deadline plus the no-re-arm rule, not by the sleep. So pick the sleep for responsiveness and API-politeness; pick the deadline for how long to wait before reminding.

`mergeStateStatus=BLOCKED` is overloaded: it covers "a required check is still running" (transient — auto-merge will fire when the check passes) and "a required check failed / approval got dismissed / branch is out of date" (terminal — needs human action). GitHub does not auto-cancel an auto-merge request when a required check fails, so `autoMergeRequest` doesn't disambiguate. The pending-check count above does: BLOCKED with at least one non-terminal check is just auto-merge waiting; BLOCKED with everything completed is a real block.

When the poller returns, branch on the final state:

- **`result=UNREACHABLE`** — the watch never once reached GitHub. Nothing is known about the PR, so **don't infer anything from the blank state fields** — it is neither still open nor merged as far as this run is concerned. Check `gh auth status` and that the `<num>`/`<repo>` pair is right, then re-spawn. This is the one return that says the watcher itself was broken rather than the PR being quiet.
- **`state=MERGED`** — run the post-merge cleanup below right away. Don't wait for the operator to re-confirm; the poller already established the merge.
- **`result=TIMEOUT`** (still `state=OPEN` after the deadline) — the watch elapsed without a merge; the operator likely stepped away. Wake **once** and tell them plainly: you watched the full window and didn't see it merge, the PR is still open and still needs merging (`<full URL>`, plus the merge command re-composed per "Composing the merge command" — check state may have changed during the wait), and they should ping you when it's done so you can run cleanup/verification. **Then stop — do not silently re-arm another watcher.** A fresh watch is cheap to start if they ask, and nothing in-session survives the session ending anyway (see below), so chaining watchers just burns one model wake per cycle for a merge only the human can trigger.
- **`state=CLOSED`** (without merge) — someone closed the PR without merging. Acknowledge, stop the workflow, leave the worktree alone in case they reopen.
- **`mergeStateStatus=DIRTY`** — a conflict developed while checks were running, typically because another PR merged into the base branch and touched the same lines. Surface the URL and the cause; ask how they want to proceed. Don't try to resolve the conflict autonomously — which side wins is their call.
- **`mergeStateStatus=BLOCKED`** (with `pending_checks=0`) — a required check failed, an **unresolved review thread** is outstanding, an approval got dismissed, or the branch is out of date with base. **`BLOCKED` is a summary over unrelated conditions and names none of them — never report a cause you haven't read off a source.** Two sessions guessed it on two PRs and got it wrong in opposite directions: "needs another review" when CI was still settling, then "BLOCKED means CI here, never review" when an inline thread was open. Read all three before saying anything:

  ```bash
  # 1. failing check — from the $J the poller already returned. Both rollup
  #    shapes, same as the PENDING count above: CheckRun has .name/.conclusion,
  #    StatusContext has .context/.state. `// []` for a PR with no checks.
  echo "$J" | jq -r '(.statusCheckRollup // [])[]
    | {n: (.name // .context), r: (.conclusion // .state)}
    | select(.r != "SUCCESS" and .r != "NEUTRAL") | "\(.n) \(.r)"'
  # 2. unresolved review threads — a hard blocker wherever required_conversation_resolution is on
  gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){
    pullRequest(number:$n){reviewThreads(first:100){nodes{isResolved path}}}}}' \
    -F o=<owner> -F r=<repo> -F n=<num> \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
  # 3. dismissed/missing approval — reviewDecision is in $J; null means no review is required at all
  ```

  Surface the URL and the specific cause you actually found, and ask how they want to proceed. A `null` `reviewDecision` means review is not a merge gate on this repo, so it rules review *out* as the cause of a block — it does not mean a review isn't wanted. The operator asked for one by sending the PR to review; that request is what the watch serves, and branch protection has no opinion on it.

**Session lifetime.** All of this lives inside the current session — a background watcher dies when the session ends, and you keep no cross-session memory that a PR is owed a watch. So the watcher covers within-a-day AFK *while the session is alive*; for a genuinely long gap (overnight, session closed) the operator pings on return and the "operator says something about the merge" path above picks it back up.

## After a merge

When told a PR has been merged (or when the merge watcher above reports `state=MERGED`), clean up **before starting any new work**, in this order:

1. Remove the worktree: `git worktree remove .worktrees/<branch-name>`
2. `git switch <default-branch> && git pull --ff-only --prune` — make sure the primary checkout is on the default branch (a no-op given the rule at the top of this skill, but cheap defense in depth against the pull silently fast-forwarding the wrong branch), then fast-forward with the merge commit. `--prune` also clears the remote-tracking branch, if the repo already deleted it on merge.
3. Delete the local branch: `git branch -d <branch-name>`. **On a squash-merge repo this fails**, and that's expected rather than a problem: a squash rewrites the commits, so the feature branch tip is never an ancestor of the base branch, and `-d` walks that ancestry and refuses. Check `allow_squash_merge` from "Know the repo's merge settings" — where squash is the repo's merge method, go straight to `git branch -D`. The operator's "merged" confirmation (or the watcher's `state=MERGED`) is what authorises the force delete; git's ancestry check can't.
4. Delete the remote branch **only if the repo doesn't do it for you**: `delete_branch_on_merge` from the settings read says which. When it's on, GitHub already deleted it and step 2's `--prune` cleared your local view — nothing to do. When it's off, `git push origin --delete <branch-name>`.

## After rebase or merge

Always review incoming changes after rebasing or merging. Don't assume the prior state is still accurate — read the changed files before answering questions about them.

## Related skills

Optional — everything above is actionable without them.

- **Your project's coding standards.** The comment bar and the
  `enforceable > prose > nothing` ordering used in "Responding to reviewers" come
  from somewhere; if your project has no standards of its own, `dnbg-practices`
  is a **separate plugin** in this marketplace that carries them —
  `/plugin install dnbg-practices@dnbg`. Nothing here assumes you have it.
