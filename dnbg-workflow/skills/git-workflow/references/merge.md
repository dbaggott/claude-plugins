# Git workflow: merge and cleanup

Part of the `git-workflow` skill. Read this once a review is clean and you are
composing the merge handoff, or when you are told a PR merged and cleanup is
owed. `references/review-rounds.md` routes here; `SKILL.md` names it for the
cold case, where this session never handled a round.

## Composing the merge command

Whenever you hand the operator a merge command, emit exactly one form — the right one for the observed state. (That's the immediately-runnable one in every case but the no-auto-merge-with-pending-checks branch below, where no immediately-runnable form exists and the handoff says so.) A clean review does not mean the PR is mergeable *right now*: a review on a fresh push usually lands while checks are still re-running, and where any of those are *required*, a plain `gh pr merge` is refused until they pass. Don't present `--auto` as an optional garnish ("add `--auto` if you want it to wait...") — you have the data to decide, so deciding is your job, not the operator's.

Two inputs. The **repo settings** — `allow_auto_merge` and which merge methods are enabled — come from `SKILL.md`'s "Know the repo's merge settings". The **live merge state** has to be read now:

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

For a multi-repo PR set (see `SKILL.md`'s "Multi-repo changes"), run both reads **per repo** — siblings can need different forms, because both the check state and the repo settings differ across repos.

**Formatting:** put each merge command on its own line in a fenced code block, never inline in a sentence or bullet — inline commands can't be cleanly triple-click-selected or copy-pasted. For a multi-PR handoff, one block with one command per line:

```
gh pr merge 247 --repo <owner>/infrastructure --squash --delete-branch --auto
gh pr merge 48 --repo <owner>/examples --squash --delete-branch
```

(Don't column-align the commands with padding spaces — extra whitespace inside a command is harmless but looks like it might not be.)

## Watching for the merge to complete

**Start it proactively.** The moment a review comes back clean (the clean-review handoff in `references/review-rounds.md`), spawn the background poller below on the PR — don't wait for the operator to announce anything. It watches until the PR merges, closes, hits a conflict, hits a terminal block, or its window elapses, then wakes you once. This removes the round-trip in the common case (operator merges right away) and the unwatched gap in the AFK case (operator merges hours later). Spawning a watcher is read-only — it never merges; only a human does.

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

**Do not hand-roll this loop** — same reasons as the review watcher in `references/review-rounds.md`. `tests/watch-merge.bats` pins every branch: merged, closed, conflicted, terminally blocked, blocked-but-still-running, timed out, unreachable, and a payload that stops parsing.

The default window is 6h of **laptop-open time**, with the poll interval on the shared curve in `scripts/lib-poll.sh`. Both are overridable (`WINDOW`, `POLL_CURVE`); the defaults are tuned for this watch. Suspended time is discounted from both, so a lid closed overnight doesn't burn the window and a resumed watch comes back responsive.

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
3. Delete the local branch: `git branch -d <branch-name>`. **On a squash-merge repo this fails**, and that's expected rather than a problem: a squash rewrites the commits, so the feature branch tip is never an ancestor of the base branch, and `-d` walks that ancestry and refuses. Check `allow_squash_merge` from `SKILL.md`'s "Know the repo's merge settings" — where squash is the repo's merge method, go straight to `git branch -D`. The operator's "merged" confirmation (or the watcher's `result=MERGED`) is what authorises the force delete; git's ancestry check can't.
4. Delete the remote branch **only if the repo doesn't do it for you**: `delete_branch_on_merge` from the settings read says which. When it's on, GitHub already deleted it and step 2's `--prune` cleared your local view — nothing to do. When it's off, `git push origin --delete <branch-name>`.

### Then close the loop, in three sections

Cleanup done, report the cycle to the operator under exactly these three headings, in this order. **Print all three every time; an empty one says so in a few words** — an omitted section reads as "nothing there" and "never considered" alike.

**Actionable is the narrow section, and doubt resolves toward Observations** — the one the operator is invited to skim. An item earns Actionable only by naming a concrete next step and where. One you already judged as not worth raising during the cycle does not earn it here: passing it on hands over the work without the judgement that would let the operator size it. A clean cycle routinely leaves the section empty.

- **Summary** — what happened. The PR by full URL, what shipped as-built, and how the cycle went (rounds, verdicts, anything the review changed about the work). Self-contained: the operator may have been away since the handoff.
- **Observations** — informational, and nothing for them to do. Something surprising in the code you touched, an assumption the change now rests on, a check that passed for a reason worth knowing.
- **Actionable** — findings deferred with "Merge as-is", a follow-up the reviewer raised that you didn't take, setup or config the merged change now needs, a defect you saw and left alone. One line each, naming the concrete next step and where.

Don't act on that list — filing and fixing are the operator's call, and `issue-workflow` covers the filing once they make it.

