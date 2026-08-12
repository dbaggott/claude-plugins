---
name: git-workflow
description: How to change any tracked file in a covered repo — worktree, draft PR, review rounds, merge handoff, post-merge cleanup. Load before you edit, write, or modify any tracked file in a covered repo (application code, skills, plugins, docs, configs, tests — anything that would show up in `git status`), and when opening a PR (including pairing PRs across repos for one multi-repo change), marking one ready, watching for or addressing review feedback, or cleaning up after a merge. The trigger is a tracked file changing, not the user's choice of words.
---

# Git workflow

This is the standard flow for any code change in a covered repo — one whose
`origin` belongs to an account in this plugin's `owners` setting. Never modify
the main checkout directly; always work in a worktree.

## This flow is GitHub-only

Every step below drives `gh` — `gh pr`, `gh api`, GraphQL `reviewThreads` — so
on another forge it is not merely degraded, it cannot run at all. Before step 1,
read the host of the repo you are about to change:

```bash
git remote get-url origin
```

**If the host is not `github.com`, stop and decline.** Say that this flow is
GitHub-only, name the host you actually found, and fall back to whatever flow
the project already uses. Do not run a `gh` command against it to "see what
happens" — the value here is a clear statement instead of a cascade of confusing
command errors, and one attempted call forfeits it. Do not translate the flow to
`glab` or another forge's CLI either: a half-working translation is worse than a
clean decline.

Two cases that are **not** a decline:

- **No `origin`.** A local-only repo, or one whose remotes are named something
  else, makes no forge claim either way. Don't degrade and don't assume GitHub —
  proceed and let the operator direct.
- **Several remotes.** `origin` decides, matching what the enforcement hooks do.

`velocity-tradeoff` ships in this same plugin and is **not** GitHub-only — it
mentions no forge and applies wherever you are. Declining is per skill, never
per plugin.

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

**`.worktrees/` is the default, not a constant.** It is configurable, so if a `dnbg-workflow` note at session start names a different worktree root, that note wins and every `.worktrees/` in this skill means the root it names — including the `git worktree add` in step 4 and the `git worktree remove` in the post-merge cleanup. With no such note, the literal above is what this session uses.

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

**Don't read branch protection to find out whether an approval still counts.** Reaching for the repo's `dismiss_stale_reviews` flag is wrong twice over. That flag lives on the branch-protection endpoint, which requires **admin** — so on a repo where you have only write access (common when contributing to an org repo you don't administer) it answers 403 or 404 and tells you nothing. And where it *does* answer, the answer misleads: `dismiss_stale_reviews: true` alongside `required_approving_review_count: 0` means no approval is required, so there is no approval gate to make stale and nothing is ever dismissed. That pairing is the default on a personal repo that gates on CI.

This is one instance of a general posture, and the general form is `reviewer`'s "Repo settings you cannot read": an unreadable setting gets assumed in whichever direction makes the behavior safe, and no instruction here may rest on one being *on*. The `UNSTABLE` arm under "Composing the merge command" is where this skill applies the other half of it.

The question that field gets reached for is always really **"is HEAD approved?"**. Where approvals are *required* — `reviewDecision` is non-null — that field answers it directly and is the primary source: it accounts for supersession and for multiple required reviewers, neither of which the check below models. Where they are not required, `reviewDecision` is `null` and says nothing, and this is what remains:

```bash
"<skill-dir>/../../scripts/pr-verdict.sh" <owner>/<repo> <num>
```

HEAD is approved **iff** the result line reads `verdict=APPROVED at_head=1`. Both halves are load-bearing, and knowing *why* is what keeps a later simplification from dropping one:

- **The latest verdict, not the latest approval.** Filtering to `APPROVED` and taking the last one reads an `APPROVED` followed by a `CHANGES_REQUESTED` at the *same* SHA as approved. Two routes reach that: a second reviewer objecting over a standing approval, and a reviewer reversing itself after a reply. Where `reviewDecision` is `null` nothing downstream catches it.
- **`COMMENTED` is not a verdict** and must stay out of the set — a reviewer answering a thread posts one, and counting it would blank the verdict on every exchange.

An approval further down the list is an approval of a diff nobody is merging. Use this wherever the answer matters — before telling the operator a PR is ready to merge, and before merging one yourself if you ever have cause to.

**Don't hand-roll the query.** `tests/pr-verdict.bats` pins each case, including the reversed approval and the `COMMENTED` exclusion. A `result=ERROR` line means the check could not see; it is not a verdict of "not approved".

For a multi-repo change, read this **per repo**. Siblings genuinely differ, and a setting borrowed from the wrong one produces a merge command that fails or a cleanup step that silently does nothing.

## Writing the PR description

The description reflects the **as-built** state (step 7) — and every claim in it must be *true and earned*. A reviewer who catches one inflated claim discounts the whole description, so the asymmetry is stark: under-claiming costs nothing, over-claiming costs trust.

- **Name what you verified, and how — don't imply more.** "Typechecks (`tsc`)" and "CI green" are not "tested"; "eyeballed one case on dev" is not "verified end-to-end." State the check you actually ran; if you didn't run one, don't phrase the body so it reads as if you did.
- **Don't assert coverage you don't have.** No unit runner for a file? Say its helpers are covered by typecheck + manual, not that they're "tested." Never describe intended or aspirational tests as existing ones.
- **Don't state impact without evidence.** Performance, cost, "fixes X for all inputs" — back it with the measurement or the reasoning, or hedge it. A confident-sounding number with no source is an over-claim.
- **Claim only the scope you checked.** The over-claim usually starts one step earlier, as an unexamined assumption written up as fact: that a change generalizes, that it fixes the root cause (not just the symptom you reproduced), that the correlation you saw is the cause, that nothing else is affected. Verify the assumption, or state the scope you actually verified ("fixes the observed case; other inputs unchecked"; "removes the symptom — root cause not confirmed"). An assumption is not a result.
- **Surface gaps, not just wins.** Known limitations, unverified branches, and deferred follow-ups belong in the body — these are as-built facts about the result, not the development narrative step 7 rules out; omitting them reads as "all handled," and the next reader inherits the surprise.

`issue-workflow` holds issue bodies to the same bar, and states it there. When unsure whether a claim is earned, weaken it or cut it — a description a reviewer can trust line-for-line is worth more than an impressive one they have to second-guess.

**If a `## dnbg-workflow <version>` note appeared at session start, end the description with the version stamp it names:**

```
<!-- dnbg-workflow <version> -->
```

It renders invisibly. It records which version of these prompts authored the PR — nothing else does, since a transcript carries the plugin's name but not its version, and transcripts expire on a rolling window while the PR does not. Re-state it when you rewrite the description under step 7; a description rewritten by a later session should carry that session's version, not the original one. With no note, take the version from nowhere else — not the manifest, not one you remember — and leave the stamp off: nothing downstream can distinguish a guessed version from a read one.

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
2. **Record state**: the current head SHA, a timestamp marking "handled up to here", and the SHA of the verdict you last handled (nothing yet, on a first arm).
3. **Spawn `watch-pr.sh`** as a **background** task (Bash `run_in_background: true`). It blocks until something happens, so its idle polling never enters the conversation, and the harness wakes you when it returns.

```bash
HEAD=$(gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid)
ME=$(gh api user --jq .login)
# Both are load-bearing, and a blank one means the `gh` call above failed — that
# is what this catches. The watcher's two responses differ, and neither reads
# clearly off its result line:
#   - A blank login is REFUSED (`result=ERROR reason=bad-args`), because the
#     exclude filter would match nobody and your own thread replies would
#     register as activity — the exact failure the fifth argument prevents.
#   - A blank head is ACCEPTED: the watcher adopts the first HEAD it observes.
#     That self-heal costs only the push it could never have seen, but here that
#     window is real, since `gh pr ready` ran moments ago.
[ -n "$HEAD" ] && [ -n "$ME" ] || { echo "could not resolve head SHA / login — re-run the watch"; exit 1; }
# WINDOW=1800 overrides the script's 6h default. That default is right for
# `reviewer`, where IDLE is routine; here IDLE means something is wrong, and a
# signal the operator waits six hours for is not a signal. A bot reviewer
# normally replies in 1–3 minutes, so 30 minutes is a generous safety net.
# --last-verdict makes the verdict check level-triggered, so a review that landed
# before this watch existed — in the gap after `gh pr ready`, or before the
# timestamp above — still wakes it instead of being invisible for the whole
# window. Empty is correct here and only here: it says "I have handled no verdict
# yet". On every re-arm pass the SHA of the verdict you last handled, or the watch
# wakes on that same verdict on its first tick, every time.
WINDOW=1800 "<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <num> \
  "$HEAD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ME" --last-verdict=
```

Both watchers trace themselves to `${TMPDIR:-/tmp}/dnbg-watch/<script>-<pid>.log` by default. When a watch returns no result line, that trace says which of three things happened: a `SIGNAL=` line (something stopped it), an `EXIT code=` line (it stopped itself), or a heartbeat and nothing after (an uncatchable kill). It is the only record — a killed watch writes no result, and the task output is empty either way.


The path reaches out of this skill's directory on purpose: the script is shared with `reviewer`, which watches the same PRs from the other side. `CLAUDE_PLUGIN_ROOT` is exported to *hook* processes, not to yours, so a skill can only address a sibling relative to its own announced Base directory — and skill directories are always `<plugin>/skills/<name>/`, which makes `../../scripts/` deterministic.

**Do not hand-roll this loop.** Three ways a hand-written version goes wrong that are not obvious until they bite:

- It polls for a review **on the current head SHA**. That is right after you push a fix, and wrong after you answer a reviewer in threads — replying moves nothing, so the filter matches the review you already handled and wakes you with stale news dressed as a fresh verdict.
- The fifth argument is the login whose activity to **ignore** — your own. This is load-bearing, not padding: replying to a review thread registers as a *review event authored by you*, with an empty body and state `COMMENTED`, so without it your own reply satisfies the wait and reports a PR as reviewed when nobody has looked. The script also handles the two spellings GitHub uses for the same bot (`<slug>` via GraphQL, `<slug>[bot]` via REST), which a hand-written filter reliably gets wrong.
- It returns on the first thing it sees. A round is a **burst** — a reviewer files a verdict and several inline comments — and returning early is *lossy* rather than merely mis-ordered, because you re-arm with `since` set to now and anything unread is filtered out permanently. The script settles before reporting.

Being a file rather than a fenced block is itself part of the fix: `shellcheck` covers `scripts/`, and covers nothing inside a `.md`.

The script prints one result line. Treat the returns differently:

- **`result=ACTIVITY`** — a review, comment or reply landed. Go to "When a review comes in".
- **`result=COMMITS`** — someone pushed to the branch. If it wasn't you, read the change before responding to anything. **If `activity=1`, comments or replies landed in the same burst — handle them in this same pass**, per "When a review comes in". This is reachable from your side: a reviewer clicking "Update branch", or applying a suggestion while filing comments, produces exactly `COMMITS activity=1`. Ignoring the flag is *permanent* loss, not deferral — you re-arm with `since` set to now, so anything unread is filtered out for good. Same failure the third bullet above gives as a reason not to hand-roll this.
- **`result=CLOSED`** — merged or closed. Stop watching; if `state=MERGED`, run the post-merge cleanup.
- **`result=ERROR reason=<source>`** — the watch itself is broken: that source failed repeatedly, so it cannot see. **Do not re-arm** — you would poll straight back into the same failure. Check `gh auth status` and the `<num>`/`<repo>` pair, then tell the operator. Unlike `IDLE` this means nothing about the PR; the watch never got a look at it.
- **`result=ERROR reason=bad-args`** — the same code, the opposite remedy. Nothing failed: the watch refused to start because an argument could not do its job. Fix the argument and re-spawn; don't go near `gh auth status`. The guard on the spawn above catches the blank-`$ME` case before it gets here, so what actually reaches you is a re-arm's argument: an abbreviated `<last_head>` or `--last-verdict` value (see the note below — both take a full 40-character SHA), or a trailing flag that is neither `--was-draft` nor `--last-verdict=<sha>`.
- **`result=IDLE`** — the window elapsed with nothing. **Here this means something is probably wrong** — a reviewer that never replied, or the wrong `<num>`/`<repo>`. Wake once and tell the operator; do **not** silently re-arm. (`reviewer` treats `IDLE` as routine and re-arms, because a quiet PR is expected on that side. Same script, opposite caller.)

  **Check whether HEAD is already approved before reporting that no review landed** — run `pr-verdict.sh` per "Know the repo's merge settings". If it is `APPROVED` at HEAD, the review is *in hand* and the watch simply missed it. `--last-verdict` above is what stops that happening, so this is the backstop for what it doesn't cover: a watch armed without the flag, and a verdict replaced at the same SHA. Reporting "no review has landed" there is a false statement about the PR, made from the watcher's blind spot rather than from the PR. If HEAD is not approved, the entry above stands and the reviewer really is the thing to check.

- **No `result=` line at all** — the task was killed or failed rather than returning. This is the dangerous one, because it looks exactly like a quiet watch while being its opposite: the watcher stopped observing, and anything pushed or posted since is unreported. **Never treat a missing result as "nothing happened."** Re-read `headRefOid` with `gh pr view` and compare against the SHA you last handled, then re-arm from what GitHub says rather than from what the watcher last told you. Traces make this diagnosable after the fact — see the trace note after the spawn block.

**A result line carrying `verdict_sha=<sha>` is the value to re-arm `--last-verdict` with.** It means the level-triggered check fired — a verdict stands at HEAD that you had not handled. No such field means it didn't fire, so carry the value you already had forward. Re-arming with an empty `--last-verdict=` after handling a verdict that is still at HEAD wakes the next watch instantly and repeatedly, since nothing about that verdict has changed.

The same spawn works after pushing a fix in response to feedback — record the new head and a fresh timestamp, and re-arm. After a push the old verdict is no longer at HEAD, so it can no longer trigger a wake whatever you pass.

⚠️ **The new head is the full 40-character SHA**, from `gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid` — never an abbreviated one you happened to print for a human. The watcher compares it as a string against what GitHub returns, so a short SHA can never match; it refuses one outright (`result=ERROR reason=bad-args`). This is the re-arm's exposure and the spawn's guard does not cover it: that guard tests `$HEAD` for *blankness*, and an abbreviated SHA is not blank. The same holds for `--last-verdict`, which is compared against `commit.oid` the same way — take it from the watcher's `verdict_sha` or from `pr-verdict.sh`, both of which report the full SHA.


## When a review comes in

**Fetch the inline comments first — the review body is not the whole review.** Findings are routinely filed on lines of the diff, and those do **not** appear in `gh pr view --json reviews`. Read them before summarizing anything:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/comments --paginate \
  --jq '.[] | "── \(.path):\(.line // .original_line)\n\(.body)\n"'
```

This is not belt-and-braces. A body reading "four things below" with three summary bullets is normal — the fourth, often the only real defect, is inline. Summarize from the body alone and the next round opens with every finding still outstanding, because none of them was ever addressed.

**And enumerate the unresolved threads — don't trust your own list of what you fixed.** Run the command rather than working from memory: a reviewer reads open threads as outstanding work, which is exactly what they mean, so a thread you believe you handled and left open reports the round as unaddressed.

```bash
"<skill-dir>/../../scripts/pr-threads.sh" <owner>/<repo> <n>
```

One JSON object per unresolved thread — `id`, `path`, `line`, `author`, `body` — then `result=OK count=<n>`. **No `--mine` here:** that flag narrows to the reviewer bot's own threads, and a human reviewer's thread blocks the merge just as surely.

Run all three — verdict, inline comments, threads — before summarizing anything. A verdict alone is a third of the review.

Read the review payload and pick one of three responses based on content. Track whether the operator has opted in to auto-handling for *this* PR — once they pick "Auto-handle all rounds" in the picker below, the choice is sticky across subsequent rounds until the PR merges or they explicitly stop.

**Clean review (APPROVED, no actionable findings).** First, **confirm the standing verdict is an approval attached to the current HEAD** — run `pr-verdict.sh` per "Know the repo's merge settings". `APPROVED` in the watcher payload only tells you an approval exists somewhere in the list; it may sit on a commit you have since pushed past, or have been superseded by a later `CHANGES_REQUESTED` from another reviewer. Where the repo doesn't dismiss stale approvals — the common case, since dismissal needs `required_approving_review_count` above 0 — the merge box shows an unqualified green check over exactly that state, so nothing on the PR will correct you. If the last verdict isn't `APPROVED` at HEAD, this isn't the clean-review case: say what the standing verdict is and which SHA it sits on, and wait for the reviewer to re-verdict (which `reviewer` now does unprompted on any HEAD move).

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
"<skill-dir>/../../scripts/pr-threads.sh" <owner>/<repo> <n> --resolve <thread-id>
```

Resolve only what you actually addressed. A thread you are declining to act on stays open with your reasoning in it — that is a disagreement to surface, not a box to tick.

⚠️ **A code comment is the last resort, and only when it would have earned its place anyway.** A reviewer's question is not a licence to add prose that fails the bar every comment has to clear: *will this still be true after the next change, and does it change what someone does?* An answer that exists only because someone asked once is transient state — if the only action a changing world requires is deleting the line, it was never a comment — and it will read as inexplicable defensiveness to the next person. If the answer is a *current, non-obvious constraint a future editor needs*, it was already worth a comment before the review; if it isn't, the PR body is where it goes.

When a finding you have already answered is re-raised, say so once and point at where the answer lives. Don't re-litigate it, and don't read the repetition as the answer having been rejected.

## Issue and PR references

Full GitHub URLs, always — per the always-on rule "Reference issues and PRs by full URL". The rationale and the memory-file exception live there.

## Composing the merge command

Whenever you hand the operator a merge command, emit exactly one form — the right one for the observed state. (That's the immediately-runnable one in every case but the no-auto-merge-with-pending-checks branch below, where no immediately-runnable form exists and the handoff says so.) A clean review does not mean the PR is mergeable *right now*: a review on a fresh push usually lands while checks are still re-running, and where any of those are *required*, a plain `gh pr merge` is refused until they pass. Don't present `--auto` as an optional garnish ("add `--auto` if you want it to wait...") — you have the data to decide, so deciding is your job, not the operator's.

Two inputs. The **repo settings** — `allow_auto_merge` and which merge methods are enabled — come from "Know the repo's merge settings" above. The **live merge state** has to be read now:

```bash
gh pr view <num> --repo <repo> --json mergeStateStatus,statusCheckRollup
```

Pick the merge-method flag from what the repo actually allows (`--squash`, `--merge`, or `--rebase`); if several are enabled, prefer the repo's own convention, and `--squash` when there's no signal. Then pick the form by state:

- **`mergeStateStatus=CLEAN`** — plain form: `gh pr merge <num> --repo <repo> <method> --delete-branch`.
- **`UNSTABLE`** — mergeable, with at least one check not passing. Hand over the same plain form, and hand it over now: GitHub will merge this PR on request, and a check the repo actually gates on never lands here (a red *required* check reads as `BLOCKED`), so there is nothing to withhold the command over. What changes is that it doesn't go out *unqualified* — `UNSTABLE` says nothing about whether the failing check was *required*, so on a repo that requires none, a completely red build arrives here looking mergeable. Name the non-passing checks alongside the command, reading the `statusCheckRollup` you already fetched above — the jq under `result=BLOCKED` below is the one place that expression is written, and it covers both rollup shapes and a PR with no checks. Split on what it reports — and where both apply, one check still running and another already failed, the failure decides the framing:
  - **Still running** — name the checks in flight and say plainly that nothing is holding the merge for them. Whether to let them land first is the operator's call, and it is not a reason to make them wait on the command. Don't reach for `--auto` here: GitHub offers auto-merge only on a PR that *can't* merge yet, and it waits on required gates, none of which are outstanding in this state.
  - **Finished non-passing** — name each check and its conclusion, and don't call the PR ready to merge. The command is still theirs to run; just be plain that nothing on the repo will stop it.
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

**Start it proactively.** The moment a review comes back clean (the clean-review handoff above), spawn the background poller below on the PR — don't wait for the operator to announce anything. It watches until the PR merges, closes, hits a conflict, hits a terminal block, or its window elapses, then wakes you once. This removes the round-trip in the common case (operator merges right away) and the unwatched gap in the AFK case (operator merges hours later). Spawning a watcher is read-only — it never merges; only a human does.

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
- **`state=OPEN`, `autoMergeRequest` null, `mergeStateStatus=BLOCKED`** — auto-merge isn't scheduled and something is blocking the merge. Don't spawn the poller; surface and ask. (Distinct from the previous case: without auto-merge enabled, a BLOCKED state needs a human to either fix the block or enable auto-merge.)
- **`state=OPEN`, `autoMergeRequest` null** — nothing scheduled. Either the operator was being forward-looking ("I'm about to merge") or thought it had merged when it hadn't. Don't spawn a second watcher; if a proactive one is already running, say so ("not merged yet — I'm still watching") and otherwise ask before assuming.

### Background poller

Spawn this as a **background** poller (Bash `run_in_background: true`) — both for the proactive watch right after a clean review (state `OPEN`, nothing scheduled yet) and whenever a verify branch above says to spawn. Background for the same reason the review watcher is: running it in the foreground replays the `gh pr view` command and every empty intermediate result into context, once per loop iteration. The window is measured from **when you spawn the poller**, not from PR creation or the review — so a verify-branch spawn hours later (e.g. the operator pings on return after the proactive watcher's session ended) still gets a full one.

```bash
"<skill-dir>/../../scripts/watch-merge.sh" <owner>/<repo> <num>
```

**Do not hand-roll this loop** — same reasons as the review watcher above. `tests/watch-merge.bats` pins every branch: merged, closed, conflicted, terminally blocked, blocked-but-still-running, timed out, unreachable, and a payload that stops parsing.

It reads only — the test suite greps it for every mutating form (`gh pr merge`/`close`/`review`, `-X POST`, `--method PUT`, ...), because a watcher that could merge is a failure nothing else would catch. A grep is a smoke test, not a proof, but it is the cheap half of one.

The default window is 6h of **laptop-open time**, and the poll interval follows the shared curve in `scripts/lib-poll.sh` — 10s at the start, easing to 30s over half an hour, a minute by the 90-minute mark, and 5 minutes thereafter. A merge that's going to happen usually happens in the first few minutes, and nearly always within the hour; past that the odds flatten and a fast poll buys nothing. Both are overridable (`WINDOW`, `POLL_CURVE`) but the defaults are tuned for exactly this watch.

**Laptop-open time, not wall-clock**, matters here more than anywhere else in this skill: a lid closed overnight must not burn the window. The shared clock discounts suspended time from both the window and the curve, so a watch resumes where it left off and comes back at the 10s floor — the responsiveness you want at exactly the moment the operator reopens the machine.

`reviewDecision` is in the JSON the script prints so the surface-and-ask branch below can identify a dismissed-approval cause without a second `gh pr view`. Read it as a *gate* question, not an approval question: `null` means no review is required to merge on this repo, which rules review out as the cause of a `BLOCKED`. It says nothing about whether HEAD is approved — that is the `commit.oid` comparison, and on a repo with `reviewDecision: null` it is the only thing that answers it.

`mergeStateStatus=BLOCKED` is overloaded: it covers "a required check is still running" (transient — auto-merge will fire when the check passes) and "a required check failed / approval got dismissed / branch is out of date" (terminal — needs human action). GitHub does not auto-cancel an auto-merge request when a required check fails, so `autoMergeRequest` doesn't disambiguate. The pending-check count above does: BLOCKED with at least one non-terminal check is just auto-merge waiting; BLOCKED with everything completed is a real block.

When the poller returns, branch on the final state:

- **`result=ERROR reason=<source>`** — that source failed for both a run of ticks and a few minutes of awake time, so the watch cannot see. Short outages (a wifi blip, the reconnect right after a lid opens) are ridden out and never produce this. Nothing is known about the PR, so **don't infer anything** — it is neither still open nor merged as far as this run is concerned. (The script prints no state line here, precisely so there is nothing stale to misread as fact.) Check `gh auth status` and that the `<num>`/`<repo>` pair is right, then re-spawn. This is the one return that says the watcher itself was broken rather than the PR being quiet.
- **`result=MERGED`** — run the post-merge cleanup below right away. Don't wait for the operator to re-confirm; the poller already established the merge.
- **`result=TIMEOUT`** (still `state=OPEN` after the window) — the watch ran its full window without a merge; the operator likely stepped away. Wake **once** and tell them plainly: the PR is still open and still needs merging (`<full URL>`, plus the merge command re-composed per "Composing the merge command" — check state may have changed during the wait), and they should ping you when it's done so you can run cleanup/verification. **Then stop — do not silently re-arm another watcher.** A fresh watch is cheap to start if they ask, and nothing in-session survives the session ending anyway (see below), so chaining watchers just burns one model wake per cycle for a merge only the human can trigger.

  The window is 6h of laptop-open time, so this genuinely means six hours of *watching* — a suspended machine doesn't spend it. Don't tell the operator how long you watched in wall-clock terms; you don't know that, and it's the wrong number anyway.
- **No `result=` line at all** — the poller was killed rather than returning. It says nothing about the PR, and silence here is especially costly: this is the watch that runs for hours while the operator is away, so a kill can swallow the merge entirely and the post-merge cleanup never runs. **Don't read it as "not merged yet."** Re-read `state` with `gh pr view`; if it merged while the watch was down, run the cleanup then.
- **`result=CLOSED`** — someone closed the PR without merging. Acknowledge, stop the workflow, leave the worktree alone in case they reopen.
- **`result=DIRTY`** — a conflict developed while checks were running, typically because another PR merged into the base branch and touched the same lines. Surface the URL and the cause; ask how they want to proceed. Don't try to resolve the conflict autonomously — which side wins is their call.
- **`result=BLOCKED`** (always with `pending_checks=0`; a block with checks still running isn't terminal and the watcher keeps waiting) — a required check failed, an **unresolved review thread** is outstanding, an approval got dismissed, or the branch is out of date with base. **`BLOCKED` is a summary over unrelated conditions and names none of them — never report a cause you haven't read off a source.** It covers a failing check, an open thread, and a dismissed approval alike, and guessing has gone wrong in both directions. Read all three before saying anything:

  ```bash
  # 1. failing check. Both rollup shapes, same as the watcher's pending count:
  #    CheckRun has .name/.status/.conclusion, StatusContext has .context/.state.
  #    An unfinished check carries no conclusion, so the line falls back to its
  #    status and names the phase — that is what the `UNSTABLE` arm above reads
  #    to tell a running check from a failed one. `// []` for a PR with no checks.
  gh pr view <num> --repo <repo> --json statusCheckRollup --jq '(.statusCheckRollup // [])[]
    | {n: (.name // .context), r: (if (.conclusion // "") == "" then (.status // .state) else .conclusion end)}
    | select(.r != "SUCCESS" and .r != "NEUTRAL") | "\(.n) \(.r)"'
  # 2. unresolved review threads — a hard blocker wherever required_conversation_resolution
  #    is on. Read the count off the result line; a non-zero one names the paths above it.
  "<skill-dir>/../../scripts/pr-threads.sh" <owner>/<repo> <num>
  # 3. dismissed/missing approval — reviewDecision is in the JSON the watcher
  #    printed; null means no review is required on this repo at all
  ```

  Surface the URL and the specific cause you actually found, and ask how they want to proceed. A `null` `reviewDecision` means review is not a merge gate on this repo, so it rules review *out* as the cause of a block — it does not mean a review isn't wanted. The operator asked for one by sending the PR to review; that request is what the watch serves, and branch protection has no opinion on it.

**Session lifetime.** All of this lives inside the current session — a background watcher dies when the session ends, and you keep no cross-session memory that a PR is owed a watch. So the watcher covers within-a-day AFK *while the session is alive*; for a genuinely long gap (overnight, session closed) the operator pings on return and the "operator says something about the merge" path above picks it back up.

## After a merge

When told a PR has been merged (or when the merge watcher above reports `result=MERGED`), clean up **before starting any new work**, in this order:

1. Remove the worktree: `git worktree remove .worktrees/<branch-name>`
2. `git switch <default-branch> && git pull --ff-only --prune` — make sure the primary checkout is on the default branch (a no-op given the rule at the top of this skill, but cheap defense in depth against the pull silently fast-forwarding the wrong branch), then fast-forward with the merge commit. `--prune` also clears the remote-tracking branch, if the repo already deleted it on merge.
3. Delete the local branch: `git branch -d <branch-name>`. **On a squash-merge repo this fails**, and that's expected rather than a problem: a squash rewrites the commits, so the feature branch tip is never an ancestor of the base branch, and `-d` walks that ancestry and refuses. Check `allow_squash_merge` from "Know the repo's merge settings" — where squash is the repo's merge method, go straight to `git branch -D`. The operator's "merged" confirmation (or the watcher's `result=MERGED`) is what authorises the force delete; git's ancestry check can't.
4. Delete the remote branch **only if the repo doesn't do it for you**: `delete_branch_on_merge` from the settings read says which. When it's on, GitHub already deleted it and step 2's `--prune` cleared your local view — nothing to do. When it's off, `git push origin --delete <branch-name>`.

### Then close the loop, in three sections

Cleanup done, report the cycle to the operator under exactly these three headings, in this order. **All three every time, "None" under an empty one, and anything that could go under either of the last two goes under Actionable** — an omitted section reads as "nothing there" and "never considered" alike, and Observations is the one the operator is invited to skim.

- **Summary** — what happened. The PR by full URL, what shipped as-built, and how the cycle went (rounds, verdicts, anything the review changed about the work). Self-contained: the operator may have been away since the handoff.
- **Observations** — informational, and nothing for them to do. Something surprising in the code you touched, an assumption the change now rests on, a check that passed for a reason worth knowing.
- **Actionable** — findings deferred with "Merge as-is", a follow-up the reviewer raised that you didn't take, setup or config the merged change now needs, a defect you saw and left alone. One line each, naming the concrete next step and where.

Don't act on that list — filing and fixing are the operator's call, and `issue-workflow` covers the filing once they make it.

## After rebase or merge

Always review incoming changes after rebasing or merging. Don't assume the prior state is still accurate — read the changed files before answering questions about them.

## Related skills

Optional — everything above is actionable without them.

- **Your project's coding standards.** The comment bar and the
  `enforceable > prose > nothing` ordering used in "Responding to reviewers" come
  from somewhere; if your project has no standards of its own, `dnbg-practices`
  is a **separate plugin** in this marketplace that carries them —
  `/plugin install dnbg-practices@dnbg`. Nothing here assumes you have it.
