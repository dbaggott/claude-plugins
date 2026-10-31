# Git workflow: waiting for the merge

Part of the `git-workflow` skill. Read this when a review comes back clean,
before telling the operator the PR is ready: the merge command comes from
`references/merge.md`, and `references/post-merge.md` takes over once it lands.

## Watching for the merge

**One script, no swap — but re-arm it from its `── re-arm ──` line for the longer wait.** `watch-pr.sh
--role=author` reports everything this stage needs: `CLOSED state=MERGED`, a
conflict as `DIRTY`, and a block nothing pending will clear as
`BLOCKED cause=terminal`. There is no merge-specific poller to reach for.

It can also return `CHECKS` (a build went red), `ACTIVITY` (someone commented
after the approval) and `IDLE`. Each of those ends the run and prints a re-arm
line: **run it, or the wait is over and the post-merge cleanup never happens.**
Only `CLOSED`, `DIRTY` and a terminal `BLOCKED` are meant to end the stage.

An `IDLE` carrying `merge=behind` means the base moved on and the branch needs an
"Update branch" click. That is not a stop — re-arm and say so, because under a
merge queue it often clears without anyone doing anything.

⚠️ **The window has to be widened, and the default will not do it.** The author
role defaults to 30 minutes because that is sized for waiting on a review, where
silence is suspect. Waiting on a merge is the opposite: the operator may step
away for hours, and a watch that idles out at 30 minutes leaves the merge
uncaught and the post-merge cleanup unrun — the exact case this stage exists for.

**Take the `── re-arm ──` line the review watch just printed, change `WINDOW=` to
`21600`, and add `--merge-stage`.** That line already carries the head it
observed, `since` set to its own `now`, the verdict it reported and the checks it
named — so this is a two-token edit. Spawn the result, and every re-arm of it, in
the background with `timeout: 7200000`. Without the timeout a headless session
stops the watch after 10 minutes, and it returns no result line.

```bash
WINDOW=21600 "<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <num> \
  <the rest of the printed line, unchanged> --merge-stage
```

⚠️ **`--merge-stage` is what makes a terminal block reportable**, and it is why
this is a different arming rather than the same one with a longer window. While a
review is running, a blocked PR is the *ordinary* state of a healthy one — with
`required_conversation_resolution` on, a single open thread is enough — so the
review watch deliberately does not stop for it. Once the review is clean, that
same state means the merge will not happen without someone acting. Every later
re-arm carries the flag forward for you.

Don't re-assemble it by hand. Reading the clock for `since` drops whatever the
reviewer posted while you were composing the handoff, and dropping
`--last-checks` re-fires a red check the caller was already told about on the
merge watch's first tick. When there is no line to edit, "No re-arm line" below
builds it from GitHub instead.

**Spawn it — the edited re-arm line above — the moment a review comes back clean**, before telling the operator
the PR is ready — the claim "I am watching for the merge now" has to be about a
watcher that is running.

An `IDLE` carrying `window_left=` does not end the wait. Six hours is longer
than one run may last, so the watch ends each run at its ceiling and carries the
rest of the window on its re-arm line. Re-arm from that line without waking
anyone.

On a bare `result=IDLE` here — six hours of laptop-open time with no merge, and
no `merge=` field naming a cause — wake **once** and say the PR is still open and
still needs merging, with the URL, the merge command re-composed, and the handoff report's Actionable items repeated, ending,
unless you are a dispatched agent, on the closing line in
`<skill-dir>/../findings-review/references/report.md`: **Your move:** merge,
with the command repeated, and no watch running. Then stop; do not silently
re-arm. An `IDLE` carrying a `merge=` field is the exception: it names a cause and has a remedy, so it is re-armed rather than stopped —
`merge=behind` wants an "Update branch" click, and `merge=unrecognised:<value>`
means the schema moved and wants the enum capture re-run.

When the operator says anything about the merge — kicking it off or asserting it
is done — verify the state before acting on the words, per
`references/post-merge.md`.

### No re-arm line

When the review watch was killed without a result, or you took over a PR whose
watch another author ran, there is no `── re-arm ──` line to edit. Build the
merge watch from GitHub instead:

```bash
"<skill-dir>/../../scripts/pr-verdict.sh" <owner>/<repo> <num>
```

Go on only when its line has `verdict=APPROVED`, `at_head=1` and
`reviewed_after_head=1`, with `review_decision` empty or `APPROVED`. A
`reviewed_after_head=unknown` is the operator's to decide, as `SKILL.md` says.
Anything else means the review is not clean, and the watch to arm is the
review one in `references/review-rounds.md`. Then spawn this in place of the
edited re-arm line, in the background with `timeout: 7200000`:

```bash
WINDOW=21600 "<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <num> \
  <head> <verdict_at> "" --role=author --last-verdict=<verdict_sha> --merge-stage
```

`<head>`, `<verdict_at>` and `<verdict_sha>` are those fields of the
`pr-verdict.sh` line. `since` is the approval's time rather than the clock, so a
comment posted after the approval still wakes the watch, and one already
answered wakes it too: check the thread before replying again. Leave
`--last-checks` off, since no printed value is left to carry, and a red check
already reported comes back on the first tick.

### On `result=BLOCKED cause=terminal`

**`cause=terminal` says the block will not clear on its own. It does not say
why, and you must never report a cause you have not read off a source.** The
underlying status is a summary over unrelated conditions — an unresolved review
thread, a dismissed approval, branch protection, a merge queue — and guessing has
gone wrong in both directions. Read both before saying anything:

```bash
# 1. unresolved review threads — a hard blocker wherever
#    required_conversation_resolution is on
"<skill-dir>/../../scripts/pr-threads.sh" <owner>/<repo> <num>
# 2. dismissed or missing approval
"<skill-dir>/../../scripts/pr-verdict.sh" <owner>/<repo> <num>
```

Surface the specific cause you found and ask (without `AskUserQuestion`:
`<skill-dir>/../issue-workflow/references/delegated.md`). A `null` `review_decision` means
review is not a merge gate on this repo, so it rules review *out* as the cause —
it does not mean a review is not wanted.

A red build is not among the causes here: the fetch separates that out, and it
reaches you as `result=CHECKS` with the failing names. Like every result, that
one ends the run — **re-arm from its printed line or the merge wait is over**.
A failure in a test the diff doesn't touch gets the one rerun that
`references/watch-results.md` gives it under `result=CHECKS`.
Reading the rollup again after a terminal block finds nothing.

On `result=DIRTY`, surface the conflict and ask (without `AskUserQuestion`:
`<skill-dir>/../issue-workflow/references/delegated.md`); don't resolve it autonomously,
since which side wins is the operator's call.

### A stacked PR whose base moved

The one exception is a stacked PR, whose description records a base head
(`SKILL.md`, step 8), when its base PR merged or was rebased. A squash or a
rebase rewrites the base's commits, so the PR still carries the old ones: on
`result=DIRTY`, or when told the base PR merged, rebase it past them. Its
merge may not conflict, so the message is the trigger as often as the watch.

When the description records `GitHub stack <n>`, GitHub rebases the PR itself,
and the forge head is what moves: your worktree's `HEAD` still carries the old
commits. So first `git -C <worktree-path> fetch origin` and test
`git -C <worktree-path> merge-base --is-ancestor <recorded base head>
origin/<branch-name>`. When it does **not** hold, GitHub has rebased the PR:
`git -C <worktree-path> reset --hard origin/<branch-name>`, do step 4, and arm
the review watch as the closing paragraph says; you rebase nothing. When it
holds, the cascade has not reached the PR, or did not run: re-read the test
every 20 seconds for up to two minutes, then go on to step 1 as for a PR in no
stack. A `DIRTY` on a head GitHub already rebased is the ordinary case: surface
and ask.

1. `git -C <worktree-path> fetch origin`, then read the base:
   `gh pr view <num> --repo <owner>/<repo> --json baseRefName`. If the base
   PR merged and this PR still targets its branch, which happens when that
   branch was not deleted, retarget it as the author:
   `gh pr edit <num> --repo <owner>/<repo> --base <default-branch>`.
   `<base>` below is the base after any retarget.
2. Test whether `origin/<base>` still carries the commits this branch was cut
   from: `git -C <worktree-path> merge-base --is-ancestor <recorded base head>
   origin/<base>`.
   - **It does not**, and the same test against `HEAD` holds: the base was
     squashed or rewritten. Go on to step 3.
   - **It does**, as after a merge commit, and the watch reported no
     `result=DIRTY`: nothing needs rebasing. Do step 4
     and skip the rest. If `pr-verdict.sh` still reads HEAD approved, go on to
     `references/merge.md`'s handoff. If not, since a retarget can dismiss an
     approval with HEAD unmoved, comment on the PR asking the reviewer to
     re-verdict the unchanged head, and arm the review watch.
   - Anything else is the ordinary case above: surface and ask.
3. Rebase and push:

   ```bash
   git -C <worktree-path> rebase --onto origin/<base> <recorded base head>
   git -C <worktree-path> push --force-with-lease
   ```

   A rebase that stops on a conflict is the ordinary case: `git rebase
   --abort`, then surface and ask.
4. In the description, drop the stacked line when the base is now the default
   branch, or record `origin/<base>`'s SHA as the new base head when it is
   not. A `GitHub stack <n>` line stays either way.

The head moved, so the review is no longer clean: arm the review watch, per
`references/review-rounds.md`, not the merge watch. The reviewer re-verdicts on
the new head, which reaches you as `ACTIVITY`, and `references/merge.md`'s
handoff follows as after any clean review.
