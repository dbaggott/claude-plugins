# Reviewer: after the watch returns

Part of the `reviewer` skill. Read this when `watch-pr.sh` returns, before
branching on what it said. `SKILL.md` carries the flow up to spawning the watch;
everything from the first return to the final report is here.

## Branch on `result=`

Each return is also a line to the operator: what came back, what you did, the PR
URL. Not a re-summary of the review — that is already on the PR, and the full
report is owed once, at `CLOSED`, under the three headings below.

- **`COMMITS`** (`new_head=…`) — the author pushed. Re-review at the new HEAD
  per `references/re-review.md`, and resolve threads the new diff addressed.
- **`ACTIVITY`** — a new review, comment, or reply (not the bot's). Handle per
  **Responding to comments and replies** in `SKILL.md`; resolve threads now
  answered.
- **`READY`** (`new_head=…`) — a draft you were holding back was marked ready.
  Review it now, as a first review; re-arm from the reported `new_head`,
  **without** `--was-draft`.
- **`CLOSED`** — the PR merged or closed. Stop watching, then finish: the
  cleanup in `references/worktree.md`, then "Report the review, in three
  sections" below.
- **`IDLE`** — nothing within the polling window. Re-arm with the same state.
- **`ERROR reason=<source>`** — that source failed repeatedly and the watch
  cannot see. **Do not re-arm**: unlike `IDLE`, this says nothing about the PR,
  so re-arming polls straight back into the same failure while reporting
  nothing wrong — the silent-blindness case the next bullet describes for a
  killed task. Check `gh auth status` and the number/repo pair, then say so
  rather than continuing to watch.
- **`ERROR reason=bad-args`** — the same code, a different cause, and the
  remedy above is the wrong one: nothing failed, the watch refused to start
  because an argument could not do its job. Fix the argument and re-spawn.
  Three reach here: an empty `<slug>` (its filter would match no login, so the
  watch wakes on its own posts), a `<last_head>` or `--last-verdict` value that
  is neither empty nor a full 40-character lowercase SHA, and a trailing
  argument that is neither `--was-draft` nor `--last-verdict=<sha>`. Don't send
  the operator to `gh auth status` for any of them.
- **No `result=` line at all** — the task was killed or failed rather than
  returning (a session ending, a reload, exit 143). This is the dangerous one,
  because it looks exactly like a quiet PR while being the opposite: the
  watcher stopped observing and anything pushed since is unreported. **Never
  treat a missing result as "nothing changed."** Re-read the current
  `headRefOid` and `reviewDecision` with `gh pr view`, and diff from the last
  SHA you actually reviewed — per `references/re-review.md` — rather than from
  whatever state the watcher last reported. Then re-arm.
  Re-arming is cheap; assuming quiet is not.

**`activity=1` on a `COMMITS` or `READY` result is not decoration — read it.** It
means comments or replies landed alongside the push, and **the JSON lines above
the result line are those comments**, emitted from the poll that saw them. The
primary result says what to do first; handle the conversation per **Responding to
comments and replies** in `SKILL.md` in the same pass as the re-review — not on
a later wake, because the re-arm below sets `since_iso` to the reported `now`,
which filters out everything already reported. Deferring those replies deletes them.

`verdict=<state>` alongside `verdict_sha=` says which verdict now stands, so you
can tell another reviewer's objection from an approval before fetching anything.
It is a branching hint; `pr-round.sh` re-reads the verdict when you act on it.

**Re-arm:** update `last_head`/`since_iso` to the values the watcher reported
(`new_head`, `now`) and spawn it again. Repeat until `CLOSED` or the operator
says to stop.

`verdict_sha` is reported the same way, and is the value to re-arm
`--last-verdict` with — it appears only when the level-triggered check fired,
so carry the previous value forward when it is absent. Re-arming with an empty
`--last-verdict=` while a verdict you have already handled still stands at HEAD
wakes every subsequent watch on its first tick.

The same applies after a watch is **paused and resumed** — an operator interrupt,
a session restart. The gap is invisible from the watcher's side, so re-establish
HEAD from GitHub before deciding anything rather than continuing from the state
you had when it stopped.

## End state

The PR merging or closing (`CLOSED`) is the *only* completion. An
`--approve` is **not** terminal — and the reason is mechanical, not stylistic: a
later push moves HEAD past the SHA your approval is attached to, so the diff
being merged has not been reviewed by anyone. That holds whether or not GitHub
dismissed the approval; where it doesn't dismiss, the merge box still shows green
over the unreviewed diff, which is the worse case. Stopping at "approved" leaves
a PR that reads as reviewed and isn't. So the reviewer stays subscribed, idling and re-arming on a
quiet-but-open PR, until the PR is actually finished. The operator can stop the
watch early; quitting the session *pauses* it (re-invoke to resume), which is not
the same as completion.

⚠️ **In the issue-scoped mode, a PR reaching `CLOSED` is not the end of the
assignment** — it is the trigger to re-discover. Completion there is a fresh
discovery pass finding no open PR *and* the issue closed; see "Discovery is
continuous" in `references/issue-mode.md`. Treating one PR's `CLOSED` as the end is exactly how the
sibling PR that opens tomorrow goes unreviewed.

## Report the review, in three sections

At `CLOSED`, once the cleanup in `references/worktree.md` is done, report the
review to the operator under exactly these three headings, in this
order. **All three every time,
"None" under an empty one, and anything that could go under either of the last
two goes under Actionable** — an omitted section reads as "nothing there" and
"never considered" alike, and Observations is the one the operator is invited to
skim.

- **Summary** — what happened. The PR by full URL, how it ended (merged, or
  closed unmerged), the verdicts you posted and the SHAs they sat on, and how
  many rounds it took. Self-contained: the operator may have sent this PR to you
  hours ago and read nothing since.
- **Observations** — informational, and nothing for them to do. A pattern worth
  knowing, a risk you checked and found handled, an area the change leaves
  untouched but adjacent.
- **Actionable** — a non-blocking finding the author didn't take, a thread you
  resolved on the author's reasoning that you still think deserves a follow-up,
  a coverage gap the merged diff carries. One line each, naming the concrete
  next step and where.

Don't act on that list — you are the reviewer, and filing or fixing is somebody
else's side of the flow.

In the issue-scoped mode this report fires **per PR**, as each one closes, and
says nothing about the assignment being over — re-discovery decides that. Report
the PR that just closed; don't write the section as a wrap-up.
