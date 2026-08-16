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

## Watching for the merge

**One script, no swap — but arm it for the longer wait.** `watch-pr.sh
--role=author` reports everything this stage needs: `CLOSED state=MERGED`, a
conflict as `DIRTY`, and a block nothing pending will clear as
`BLOCKED cause=terminal`. There is no merge-specific poller to reach for.

⚠️ **The window has to be widened, and the default will not do it.** The author
role defaults to 30 minutes because that is sized for waiting on a review, where
silence is suspect. Waiting on a merge is the opposite: the operator may step
away for hours, and a watch that idles out at 30 minutes leaves the merge
uncaught and the post-merge cleanup unrun — the exact case this stage exists for.
So arm it explicitly:

```bash
WINDOW=21600 "<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <num> \
  "$HEAD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "" --role=author --last-verdict=<sha>
```

**Spawn it the moment a review comes back clean**, before telling the operator
the PR is ready — the claim "I am watching for the merge now" has to be about a
watcher that is running.

On `result=IDLE` here — six hours of laptop-open time with no merge — wake
**once** and say the PR is still open and still needs merging, with the URL and
the merge command re-composed. Then stop; do not silently re-arm.

Any time the operator says something about the merge — kicking it off
("merging", "auto-merge is on", "go ahead") **or asserting it is done**
("merged", "it is merged", "done") — **verify state with `gh pr view` before
acting on the words**. Operators use "merged" for both "the button was clicked,
auto-merge is queued" and "GitHub shows merged"; same phrasing, different states.

```bash
gh pr view <num> --repo <repo> --json state,mergeStateStatus,autoMergeRequest
```

- **`state=MERGED`** — run the post-merge cleanup below. If a watch is still in
  flight it will report `CLOSED state=MERGED` shortly; ignore the duplicate
  rather than cleaning up twice.
- **`state=CLOSED`** without a merge — acknowledge, stop, leave the worktree in
  case they reopen.
- **`state=OPEN`, `autoMergeRequest` non-null** — auto-merge is scheduled and a
  running watch will catch it.
- **`state=OPEN`, nothing scheduled** — either they were being forward-looking or
  it has not merged. Say so; don't start a second watch.

### On `result=BLOCKED cause=terminal`

**`cause=terminal` says the block will not clear on its own. It does not say
why, and you must never report a cause you have not read off a source.** The
underlying status is a summary over unrelated conditions — a failed required
check, an unresolved review thread, a dismissed approval, a branch behind base —
and guessing has gone wrong in both directions. Read all three before saying
anything:

```bash
# 1. failing checks — both rollup shapes, already normalised by the fetch
"<skill-dir>/../../scripts/fetch-pr-state.sh" <owner>/<repo> <num> \
  | head -1 | jq -r '.checks[] | select(.state == "failure") | .name'
# 2. unresolved review threads — a hard blocker wherever
#    required_conversation_resolution is on
"<skill-dir>/../../scripts/pr-threads.sh" <owner>/<repo> <num>
# 3. dismissed or missing approval
"<skill-dir>/../../scripts/pr-verdict.sh" <owner>/<repo> <num>
```

Surface the specific cause you found and ask. A `null` `review_decision` means
review is not a merge gate on this repo, so it rules review *out* as the cause —
it does not mean a review is not wanted.

On `result=DIRTY`, surface the conflict and ask; don't resolve it autonomously,
since which side wins is the operator's call.

## After a merge

When told a PR has been merged (or when the watch above reports `CLOSED state=MERGED`), clean up **before starting any new work**, in this order:

1. Remove the worktree: `git worktree remove .worktrees/<branch-name>`
2. `git switch <default-branch> && git pull --ff-only --prune` — make sure the primary checkout is on the default branch (a no-op given the rule at the top of this skill, but cheap defense in depth against the pull silently fast-forwarding the wrong branch), then fast-forward with the merge commit. `--prune` also clears the remote-tracking branch, if the repo already deleted it on merge.
3. Delete the local branch: `git branch -d <branch-name>`. **On a squash-merge repo this fails**, and that's expected rather than a problem: a squash rewrites the commits, so the feature branch tip is never an ancestor of the base branch, and `-d` walks that ancestry and refuses. Check `allow_squash_merge` from `SKILL.md`'s "Know the repo's merge settings" — where squash is the repo's merge method, go straight to `git branch -D`. The operator's "merged" confirmation (or the watch's `CLOSED state=MERGED`) is what authorises the force delete; git's ancestry check can't.
4. Delete the remote branch **only if the repo doesn't do it for you**: `delete_branch_on_merge` from the settings read says which. When it's on, GitHub already deleted it and step 2's `--prune` cleared your local view — nothing to do. When it's off, `git push origin --delete <branch-name>`.

### Then close the loop, in three sections

Cleanup done, report the cycle to the operator under exactly these three headings, in this order. **Print all three every time; an empty one says so in a few words** — an omitted section reads as "nothing there" and "never considered" alike.

**Actionable is the narrow section, and doubt resolves toward Observations** — the one the operator is invited to skim. An item earns Actionable only by naming a concrete next step and where. One you already judged as not worth raising during the cycle does not earn it here: passing it on hands over the work without the judgement that would let the operator size it. A clean cycle routinely leaves the section empty.

- **Summary** — what happened. The PR by full URL, what shipped as-built, and how the cycle went (rounds, verdicts, anything the review changed about the work). Self-contained: the operator may have been away since the handoff.
- **Observations** — informational, and nothing for them to do. Something surprising in the code you touched, an assumption the change now rests on, a check that passed for a reason worth knowing.
- **Actionable** — findings deferred with "Merge as-is", a follow-up the reviewer raised that you didn't take, setup or config the merged change now needs, an out-of-scope defect you left alone. One line each, naming the concrete next step and where. Out of scope is what qualifies a deferral, not merely having decided against it.

Don't act on that list — filing and fixing are the operator's call, and `issue-workflow` covers the filing once they make it.

