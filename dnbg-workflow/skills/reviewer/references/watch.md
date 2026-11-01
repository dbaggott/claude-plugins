# Reviewer: after the watch returns

Part of the `reviewer` skill. Read this on the session's first return of
`watch-pr.sh`, before branching on what it said, and act on that copy at later
returns. Read it again when a result is `ERROR`, when a watch returns no
`result=` line, or when the context has been compacted since you read it.
`SKILL.md` carries the flow up to spawning the watch; everything from the first
return to the final report is here.

## Branch on `result=`

Every result line carries `act=`, the branch below that its result takes for
the reviewer:

| `act=` | Results | What to do |
|---|---|---|
| `round` | `COMMITS`, `ACTIVITY`, `READY` | Read the `── round ──` file (fallback: run the `── next ──` command) first: the diff, bodies, threads and verdict the result's entry reads from. |
| `rearm` | `IDLE` | Re-arm from the printed line, as its entry says. |
| `read` | `CLOSED`, `ERROR` | Act on its entry below. |

Each return is also a line to the operator: what came back, what you did, the PR
URL. Not a re-summary of the review — that is already on the PR, and the reports
are owed at an approval and at `CLOSED`, per "Report the review" below. A turn
that ends with one of those reports opens with its first line, and the return's
line goes into the Summary of the report on that PR: the dispatcher recognises
each report by its first line.

- **`COMMITS`** (`new_head=…`) — the author pushed. Re-review at the new HEAD
  per `references/re-review.md`, and resolve threads the new diff addressed.
- **`ACTIVITY`** — a new review, comment, or reply (not the bot's). Handle per
  **Responding to comments and replies** in `SKILL.md`; resolve threads now
  answered.
- **`READY`** (`new_head=…`) — a draft you were holding back was marked ready.
  Review it now, as a first review; re-arm from the reported `new_head`,
  **without** `--was-draft`.
- **`CLOSED`** — the PR merged or closed. Stop watching, then finish under
  "Report the review" below. **Read
  `references/worktree.md` only if this *review* made a checkout or a scratch
  directory, or ran `fetch-tree.sh`** — a checkout an earlier session made and
  this one resumed included. A review that read only through `gh` calls and
  never ran `fetch-tree.sh` has nothing to remove.
- **`checks='<names>'`** on `COMMITS`, `ACTIVITY` or `READY` — a check on the
  watched head is failing. A red build alone never wakes you. It is not your
  finding to fix and not a re-review: note it in your reply if it touches what
  you asked for. The names are shell-quoted because forge check names contain
  spaces.
- **`IDLE`** — nothing within the polling window, or, with `window_left=`, a run
  cut short at the watch's wall-clock ceiling. Re-arm from the printed line either way.
- **`ERROR reason=<source>`** — that source failed repeatedly and the watch
  cannot see. **Do not re-arm**: unlike `IDLE`, this says nothing about the PR,
  so re-arming polls straight back into the same failure while reporting
  nothing wrong — the silent-blindness case the next bullet describes for a
  killed task. Check `gh auth status` and the number/repo pair, then say so
  rather than continuing to watch.
- **`ERROR reason=bad-args`** — the same code, a different cause, and the
  remedy above is the wrong one: nothing failed, the watch refused to start
  because an argument could not do its job. Fix the argument and re-spawn: a
  missing or misspelled `--role` (it is required, and only `author` or
  `reviewer` are accepted), an empty `<slug>` (its filter would match no login,
  so the watch wakes on its own posts), a `<last_head>` or `--last-verdict`
  value that is neither empty nor a full 40-character lowercase SHA, or a
  trailing argument outside the accepted set. An author-side watch that
  cannot get its own login from the role resolver reports `reason=role`
  instead. On the reviewer side you pass the slug, so it cannot be that.
- **No `result=` line at all** — the task was killed or failed rather than
  returning (a session ending, a reload, exit 143). This is the dangerous one,
  because it looks exactly like a quiet PR while being the opposite: the
  watcher stopped observing and anything pushed since is unreported. **Never
  treat a missing result as "nothing changed."** Re-read the current
  `headRefOid` and `reviewDecision` with `gh pr view`, and diff from the last
  SHA you actually reviewed — per `references/re-review.md` — rather than from
  whatever state the watcher last reported. Then re-arm.
  Re-arming is cheap; assuming quiet is not.

**`activity=1` on any result is not decoration — read it.** It means comments
or replies landed alongside whatever the result names. `activity=0` means the
burst was something else — a verdict, a check — so there is nothing
conversational to go looking for. The JSON lines above the result line say what
landed and from whom; **the text is in the `── round ──` file**: read it.
The primary result says what to do first; handle the conversation per
**Responding to comments and replies** in `SKILL.md` in the same pass as the
re-review — not on a later wake, because the re-arm below sets `since_iso` to
the reported `now`, which filters out everything already reported. Deferring
those replies deletes them.

`verdict=<state>` alongside `verdict_sha=` says which verdict now stands, so you
can tell another reviewer's objection from an approval before fetching anything.
It is a branching hint; `pr-round.sh` re-reads the verdict when you act on it.

**Re-arm from the `── re-arm ──` line the watch prints, not from values you
assemble.** It carries the next invocation with every piece of state already
filled in — the head it observed, `since` set to its own `now`, the verdict it
reported, the checks it named. Run it as printed.

Assembling it yourself is what loses a round: the interval between the
watcher's reading and yours is observed by no watch, and reading the clock
instead of carrying the reported `now` filters out anything that landed in that
gap. Commits and verdicts survive it — both are level-triggered, by head SHA and
by `--last-verdict` — but comments, replies and `COMMENTED` reviews are counted
against `since`, so anything conversational landing there is dropped
indistinguishably from silence.

`CLOSED`, `ERROR`, `DIRTY` and `BLOCKED` print no re-arm line, because none of
the four clears without a human. (Those are author-role results; a reviewer sees
only `CLOSED` and `ERROR` of them.) A killed task prints no result line, at most
the `alive` heartbeats it printed while running — that is the one case where you
rebuild the arguments yourself, per the bullet above.

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
quiet-but-open PR, until the PR is actually finished; the handoff an approval
carries does not end the review. The operator can stop the
watch early; quitting the session *pauses* it (re-invoke to resume), which is not
the same as completion.

⚠️ **In the issue-scoped mode, a PR reaching `CLOSED` is not the end of the
assignment** — it is the trigger to re-discover. Completion there is a fresh
discovery pass finding no open PR *and* the issue closed; see "Discovery is
continuous" in `references/issue-mode-wait.md`. Treating one PR's `CLOSED` as the end is exactly how the
sibling PR that opens tomorrow goes unreviewed.

## Report the review

Report per `<skill-dir>/../findings-review/references/report.md`, at two
moments on each PR:

- **The handoff**, ending the turn that posts an `APPROVE` (`SKILL.md`, "Watch
  the PR"). Its first line is exactly
  `**Reviewer handoff: APPROVED at <sha>**`, with the full 40-character head
  SHA the approval sits on, then the full report. An `APPROVE` on a later head
  carries a fresh handoff, the same first line with the new SHA, as a delta
  against the previous one. Unless you are a dispatched agent, the handoff turn
  ends on `**Done:**`, naming each watch still running and what ends it: the PR
  watch ends at `CLOSED`, and in the issue-scoped mode the assignment runs on
  past it to a fresh discovery ("End state" above), with the issue wait named
  too when it is armed. Its notification carries the verdict and the short head
  SHA. The handoff carries no merge guidance: no merge command, no "ready to
  merge", and no pointer to an author's handoff. The merge command is composed
  from merge state you never read, and the PR may have no agent author; where
  one exists, its handoff arrives on its own.
- **The close-out**, at `CLOSED`. Its first line is exactly
  `**Reviewer close-out: merged**` or `**Reviewer close-out: closed unmerged**`,
  then a delta against your last handoff, as the report's "A report after a
  handoff" says, or the full report where you have none, as when the PR closed
  without an approval.

Under the headings:

- **Summary**: the PR, the verdicts you posted and the SHAs they sat on, how
  many rounds it took, and, at the close-out, how it ended.
- **Observations**: a pattern worth knowing, a risk you checked and found
  handled, an area the change leaves untouched but adjacent, and a finding the
  author declined in a reply saying the operator told it to.
- **Actionable**: any other finding you raised that stands unaddressed, a
  thread you resolved on the author's reasoning that you still think deserves a
  follow-up, a coverage gap the diff carries.

One turn can owe several reports, as when the issue-scoped mode approves one PR
on the wake that another merged. Give each report its own first line at the
start of a line, with the complete report under it, its Summary naming its PR,
before the next begins; the turn opens with the first, and a report carrying the
assignment's end comes last. The layout holds for
any report this skill gives a first line. Start a line with one of those first
lines only to open a report: one quoted at the start of a line reads as a report
of its own.

Write each item's findings entry in the report that first lists it, which is
the handoff whenever there is one, per
`<skill-dir>/../findings-review/references/entry.md`, and name its path on the
item's line. The operator-ordered decline gets none. Process friction that did
not stop the review stays out of the handoff, Actionable included, and is not
offered for filing there: it waits for your close-out, per `report.md`'s "At a
close-out", which in the issue-scoped mode is the assignment's end, not a PR's
`CLOSED`.

Reviewing one PR, that `CLOSED` is your close-out: close out per
`<skill-dir>/../process-review/references/retrospective.md`, "When a
retrospective is written".

In the issue-scoped mode both reports fire **per PR**, and the close-out says
nothing about the assignment being over: re-discovery decides that, and the
retrospective prompt waits for the assignment's end
(`references/issue-mode-wait.md`, step 4). Report the PR that just closed;
don't write the section as a wrap-up.
The assignment's end is a report of its own, opening
`**Reviewer close-out: assignment ended**`, which that step gives.
