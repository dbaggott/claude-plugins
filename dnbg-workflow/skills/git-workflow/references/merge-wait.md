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
named — so this is a two-token edit:

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
merge watch's first tick.

**Spawn it — the edited re-arm line above — the moment a review comes back clean**, before telling the operator
the PR is ready — the claim "I am watching for the merge now" has to be about a
watcher that is running.

On a bare `result=IDLE` here — six hours of laptop-open time with no merge, and
no `merge=` field naming a cause — wake **once** and say the PR is still open and
still needs merging, with the URL and the merge command re-composed. Then stop;
do not silently re-arm. An `IDLE` carrying a `merge=` field is the exception: it
names a cause and has a remedy, so it is re-armed rather than stopped —
`merge=behind` wants an "Update branch" click, and `merge=unrecognised:<value>`
means the schema moved and wants the enum capture re-run.

Any time the operator says something about the merge — kicking it off
("merging", "auto-merge is on", "go ahead") **or asserting it is done**
("merged", "it is merged", "done") — **verify state with `gh pr view` before
acting on the words**. Operators use "merged" for both "the button was clicked,
auto-merge is queued" and "GitHub shows merged"; same phrasing, different states.

```bash
gh pr view <num> --repo <repo> --json state,autoMergeRequest
```

- **`state=MERGED`** — run the post-merge cleanup in `references/post-merge.md`. If a watch is still in
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
Reading the rollup again after a terminal block finds nothing.

On `result=DIRTY`, surface the conflict and ask (without `AskUserQuestion`:
`<skill-dir>/../issue-workflow/references/delegated.md`); don't resolve it autonomously,
since which side wins is the operator's call.
