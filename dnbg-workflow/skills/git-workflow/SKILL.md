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

One more setting lives on a different endpoint and requires **admin** on the repo:

```bash
gh api repos/<owner>/<repo>/branches/<default-branch>/protection \
  --jq '.required_pull_request_reviews.dismiss_stale_reviews'
```

On a repo where you have only write access — common when contributing to an org repo you don't administer — that call answers 403 or 404. **That is not an error and not a signal.** Fall back to observation: if a push visibly dropped a previous approval, stale dismissal is on. Until you have one of those two signals, treat it as unknown and say so rather than guessing.

For a multi-repo change, read this **per repo**. Siblings genuinely differ, and a setting borrowed from the wrong one produces a merge command that fails or a cleanup step that silently does nothing.

## Writing the PR description

The description reflects the **as-built** state (step 7) — and every claim in it must be *true and earned*. A reviewer who catches one inflated claim discounts the whole description, so the asymmetry is stark: under-claiming costs nothing, over-claiming costs trust. This is the always-on "report outcomes faithfully" rule applied to the PR body.

- **Name what you verified, and how — don't imply more.** "Typechecks (`tsc`)" and "CI green" are not "tested"; "eyeballed one case on dev" is not "verified end-to-end." State the check you actually ran; if you didn't run one, don't phrase the body so it reads as if you did.
- **Don't assert coverage you don't have.** No unit runner for a file? Say its helpers are covered by typecheck + manual, not that they're "tested." Never describe intended or aspirational tests as existing ones.
- **Don't state impact without evidence.** Performance, cost, "fixes X for all inputs" — back it with the measurement or the reasoning, or hedge it. A confident-sounding number with no source is an over-claim.
- **Claim only the scope you checked.** The over-claim usually starts one step earlier, as an unexamined assumption written up as fact: that a change generalizes, that it fixes the root cause (not just the symptom you reproduced), that the correlation you saw is the cause, that nothing else is affected. Verify the assumption, or state the scope you actually verified ("fixes the observed case; other inputs unchecked"; "removes the symptom — root cause not confirmed"). An assumption is not a result.
- **Surface gaps, not just wins.** Known limitations, unverified branches, and deferred follow-ups belong in the body — these are as-built facts about the result, not the development narrative step 7 rules out; omitting them reads as "all handled," and the next reader inherits the surprise.

The bar is the one `issue-workflow` sets for issue bodies: a *verified* anchor beats a *confident* one. When unsure whether a claim is earned, weaken it or cut it — a description a reviewer can trust line-for-line is worth more than an impressive one they have to second-guess.

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
2. Spawn a **background** poller (Bash `run_in_background: true`) that waits for a review on the *current* head SHA. The harness notifies you when the command completes, so the polling loop's transient empty results never land in the conversation:

```bash
HEAD=$(gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid)
ME=$(gh api user --jq .login)
# A blank HEAD or ME (transient gh/network failure) makes the match below
# unsatisfiable or unfiltered, so bail rather than spin. Re-spawn the watch.
[ -n "$HEAD" ] && [ -n "$ME" ] || { echo "could not resolve head SHA / login — re-run the watch"; exit 1; }
# Deadline: a review that never lands (reviewer bot down, wrong SHA) must not
# dead-spin. A bot reviewer normally replies in 1–3 min, so 30 min is a generous
# safety net; when it fires, something is wrong — wake and tell the operator,
# don't silently re-spawn into a possibly-endless wait (see below).
deadline=$(( $(date +%s) + 1800 ))
until
  # `2>/dev/null` keeps a transient blip from printing an error that survives in
  # the task output, making a working watch read like a failed one. The `if`
  # records that at least one poll reached GitHub: without it, an auth failure or
  # a wrong <num>/<repo> is invisible for the full 30 minutes and then reports
  # TIMEOUT — indistinguishable from a reviewer that simply never replied, which
  # sends the operator to check a reviewer that was never the problem.
  if R=$(gh pr view <num> --repo <repo> --json reviews \
         --jq ".reviews | map(select(.commit.oid == \"$HEAD\" and .author.login != \"$ME\")) | last" 2>/dev/null)
  then reached=1; else R=""; fi
  [ -n "$R" ] || [ "$(date +%s)" -ge "$deadline" ]
do
  sleep 15
done
[ -n "${reached:-}" ] || { echo "result=UNREACHABLE: never reached GitHub in 30m — check gh auth and the <num>/<repo> pair, not the reviewer"; exit 2; }
[ -n "$R" ] || { echo "result=TIMEOUT: no review on $HEAD after 30m"; exit 2; }
gh pr view <num> --repo <repo> --json reviews \
  --jq ".reviews | map(select(.commit.oid == \"$HEAD\" and .author.login != \"$ME\")) | last | {state, body}"
```

**The `.author.login != "$ME"` filter is load-bearing, not defensive padding.** Replying to a review thread registers as a *review event authored by you*, with an empty body and state `COMMENTED`. Without the filter, answering a reviewer's inline comment satisfies the loop's exit condition, and the watch returns your own reply dressed as the review you were waiting for — reporting a PR as reviewed when nobody has looked at the new commits yet. This is the mirror of the guard `reviewer`'s `watch-pr.sh` applies on its side (excluding the bot's own activity so it never wakes to react to itself); both watchers need it, pointed at their own identity.

The guards and deadline are not optional polish: the loop's only exit is a review appearing on `$HEAD`, so anything that makes that unreachable — an empty `$HEAD` from a transient `gh` failure, a SHA that never gets reviewed — turns it into a silent runaway shell that polls forever. Each becomes a clean exit you get notified about. Treat the three returns differently:

- **Blank `$HEAD`/`$ME` exit** — a transient hiccup at spawn time. Re-spawn the watch once.
- **`result=UNREACHABLE`** — 30 minutes without one successful poll. The watcher was broken, not the reviewer: check `gh auth status` and that the `<num>`/`<repo>` pair is right, fix it, and re-spawn. Don't report to the operator that no review has landed — you don't know that.
- **`result=TIMEOUT`** — GitHub was reachable and 30 minutes passed with no review on `$HEAD` (reviewer down, or the wrong SHA is being watched). **Don't silently re-spawn** — tell the operator no review has landed and ask whether to keep waiting or check the reviewer.

Silent re-spawning on any of them just turns one runaway shell into a chain of them, one model wake per cycle.

**Don't poll in the foreground unless the user asks for live status.** Foreground polling replays the `gh pr view` command line and every empty intermediate result into context every loop iteration — roughly 10× the conversation tokens of the background pattern for no end-state benefit. A bot reviewer typically responds in 1–3 minutes; 15-second sleeps catch it without busy-waiting.

The same pattern works after pushing a fix in response to feedback — the head SHA changes, and if the repo dismisses stale approvals (see "Know the repo's merge settings") the previous review dismisses on push. Either way the poller catches the next review on the new SHA.

## When a review comes in

Read the review payload and pick one of three responses based on content. Track whether the operator has opted in to auto-handling for *this* PR — once they pick "Auto-handle all rounds" in the picker below, the choice is sticky across subsequent rounds until the PR merges or they explicitly stop.

**Clean review (APPROVED, no actionable findings).** Tell the operator the PR is ready to merge, then **immediately spawn the merge watcher** (see "Watching for the merge to complete" → start it proactively) so the merge is caught whenever they trigger it — no round-trip if they merge right away, no unwatched gap if they step away first. Include the full URL (browser path) alongside the merge command (CLI path), framed as equals. Compose `<merge command>` per "Composing the merge command" below — hand over exactly one form, the one that will work:

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

Spawn this as a **background** poller (Bash `run_in_background: true`) — both for the proactive watch right after a clean review (state `OPEN`, nothing scheduled yet) and whenever a verify branch above says to spawn. Same rationale as the review watcher: running it in the foreground replays the `gh pr view` command and every empty intermediate result into context. The deadline below is measured from **when you spawn the poller**, not from PR creation or the review — so a verify-branch spawn hours later (e.g. the operator pings on return after the proactive watcher's session ended) still gets a full window.

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

`reviewDecision` is included so the surface-and-ask branch below can identify a dismissed-approval cause from the same JSON the poller already returned — no extra `gh pr view` call.

Sleep 60s, not the review watcher's 15s — match the interval to how fast the watched thing moves (merges take minutes-to-hours; reviews land in 1–3 min), *not* to cost. The loop's intermediate iterations run in the background and never enter the conversation, so poll frequency costs no tokens — only GitHub API calls. The token cost is the single model wake when the loop exits, and that's set by the deadline plus the no-re-arm rule, not by the sleep. So pick the sleep for responsiveness and API-politeness; pick the deadline for how long to wait before reminding.

`mergeStateStatus=BLOCKED` is overloaded: it covers "a required check is still running" (transient — auto-merge will fire when the check passes) and "a required check failed / approval got dismissed / branch is out of date" (terminal — needs human action). GitHub does not auto-cancel an auto-merge request when a required check fails, so `autoMergeRequest` doesn't disambiguate. The pending-check count above does: BLOCKED with at least one non-terminal check is just auto-merge waiting; BLOCKED with everything completed is a real block.

When the poller returns, branch on the final state:

- **`result=UNREACHABLE`** — the watch never once reached GitHub. Nothing is known about the PR, so **don't infer anything from the blank state fields** — it is neither still open nor merged as far as this run is concerned. Check `gh auth status` and that the `<num>`/`<repo>` pair is right, then re-spawn. This is the one return that says the watcher itself was broken rather than the PR being quiet.
- **`state=MERGED`** — run the post-merge cleanup below right away. Don't wait for the operator to re-confirm; the poller already established the merge.
- **`result=TIMEOUT`** (still `state=OPEN` after the deadline) — the watch elapsed without a merge; the operator likely stepped away. Wake **once** and tell them plainly: you watched the full window and didn't see it merge, the PR is still open and still needs merging (`<full URL>`, plus the merge command re-composed per "Composing the merge command" — check state may have changed during the wait), and they should ping you when it's done so you can run cleanup/verification. **Then stop — do not silently re-arm another watcher.** A fresh watch is cheap to start if they ask, and nothing in-session survives the session ending anyway (see below), so chaining watchers just burns one model wake per cycle for a merge only the human can trigger.
- **`state=CLOSED`** (without merge) — someone closed the PR without merging. Acknowledge, stop the workflow, leave the worktree alone in case they reopen.
- **`mergeStateStatus=DIRTY`** — a conflict developed while checks were running, typically because another PR merged into the base branch and touched the same lines. Surface the URL and the cause; ask how they want to proceed. Don't try to resolve the conflict autonomously — which side wins is their call.
- **`mergeStateStatus=BLOCKED`** (with `pending_checks=0`) — a required check failed, an approval got dismissed, or the branch is out of date with base. Inspect `statusCheckRollup` in the returned `$J` to identify the failing check, and `reviewDecision` (also in `$J`) for a dismissed-approval cause. Surface the URL and the specific cause, and ask how they want to proceed.

**Session lifetime.** All of this lives inside the current session — a background watcher dies when the session ends, and you keep no cross-session memory that a PR is owed a watch. So the watcher covers within-a-day AFK *while the session is alive*; for a genuinely long gap (overnight, session closed) the operator pings on return and the "operator says something about the merge" path above picks it back up.

## After a merge

When told a PR has been merged (or when the merge watcher above reports `state=MERGED`), clean up **before starting any new work**, in this order:

1. Remove the worktree: `git worktree remove .worktrees/<branch-name>`
2. `git switch <default-branch> && git pull --ff-only --prune` — make sure the primary checkout is on the default branch (a no-op given the rule at the top of this skill, but cheap defense in depth against the pull silently fast-forwarding the wrong branch), then fast-forward with the merge commit. `--prune` also clears the remote-tracking branch, if the repo already deleted it on merge.
3. Delete the local branch: `git branch -d <branch-name>`. **On a squash-merge repo this fails**, and that's expected rather than a problem: a squash rewrites the commits, so the feature branch tip is never an ancestor of the base branch, and `-d` walks that ancestry and refuses. Check `allow_squash_merge` from "Know the repo's merge settings" — where squash is the repo's merge method, go straight to `git branch -D`. The operator's "merged" confirmation (or the watcher's `state=MERGED`) is what authorises the force delete; git's ancestry check can't.
4. Delete the remote branch **only if the repo doesn't do it for you**: `delete_branch_on_merge` from the settings read says which. When it's on, GitHub already deleted it and step 2's `--prune` cleared your local view — nothing to do. When it's off, `git push origin --delete <branch-name>`.

## After rebase or merge

Always review incoming changes after rebasing or merging. Don't assume the prior state is still accurate — read the changed files before answering questions about them.
