# Git workflow: review rounds

Part of the `git-workflow` skill. Read this when the operator sends the PR to
review, before spawning anything. `SKILL.md` carries the flow up to that point;
`references/review-received.md` takes over when a review comes in.

## Watching for the first review

When the operator picks "Send to review" in `SKILL.md`'s picker, or otherwise signals the PR is ready (says "ready", "go", "mark it ready", etc.):

1. Note the time, then run `gh pr ready <num> --repo <repo>` if the PR isn't already out of draft. That time is the first arm's `since`, per the first-arm rule in `watch-issue.sh`'s header: the review responds to this step. A PR already out of draft was ready before this step, so its review responds to your last push instead: take `since` from your last commit, `gh pr view <num> --repo <repo> --json commits --jq '.commits[-1].committedDate'`, which is no later than the push.
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
  "$HEAD" "<the time you noted in step 1>" "" --role=author --last-verdict=
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

- **`result=ACTIVITY`** — a review, comment or reply landed. Go to `references/review-received.md`.
- **`result=COMMITS`** — someone pushed to the branch. **Reviewer role only**: this role cannot tell your push from anyone else's, so it reports none of them rather than waking you on your own. A third party's push is not lost by that — it is not *announced*, but the head the re-arm carries does not advance past it, so the next round's `── next ──` diff still spans it. A reviewer who pushes *and* comments does wake you, as `ACTIVITY`, and that diff covers the push too.
- **`activity=1` on any burst** — comments or replies landed alongside whatever the result names. **Handle them in this same pass**, per `references/review-received.md`. Ignoring the flag is *permanent* loss, not deferral — you re-arm with `since` set to now, so anything unread is filtered out for good. `activity=0` means the burst was something else (a verdict, a check), so there is no conversation to go looking for.
- **`result=CLOSED`** — merged or closed. Stop watching; if `state=MERGED`, run the post-merge cleanup in `references/post-merge.md`.
- **`result=ERROR reason=<source>`** — the watch itself is broken: that source failed repeatedly, so it cannot see. **Do not re-arm** — you would poll straight back into the same failure. Check `gh auth status` and the `<num>`/`<repo>` pair, then tell the operator. Unlike `IDLE` this means nothing about the PR; the watch never got a look at it.
- **`result=ERROR reason=bad-args`** — the watch refused to start because an argument could not do its job. Usually a re-arm's argument: an abbreviated `<last_head>` or `--last-verdict` value (see the note below — both take a full 40-character SHA), a missing `--role`, or a trailing flag outside the accepted set. Fix it and re-spawn. **The exception is auth**: this role derives its own login from `gh api user`, and a failure there produces an empty slug, which the watch refuses. So unlike the other bad arguments, `gh auth status` is worth a look when nothing in the command line is obviously wrong.
- **`result=IDLE`** — the window elapsed with nothing. **Here this means something is probably wrong** — a reviewer that never replied, or the wrong `<num>`/`<repo>`. Wake once and tell the operator; do **not** silently re-arm. (The reviewer role treats `IDLE` as routine, which is why the role is an argument rather than a caller convention.)

  **Check whether HEAD is already approved before reporting that no review landed** — run `pr-verdict.sh` per `SKILL.md`'s "Know the repo's merge settings". If it is `APPROVED` at HEAD, the review is *in hand* and the watch simply missed it. Reporting "no review has landed" over a standing approval is a false statement about the PR, made from the watcher's blind spot rather than from the PR. If HEAD is not approved, the entry above stands.

- **`result=CHECKS checks='<names>'`** — a check on the watched head stopped passing. Read it before telling the reviewer a finding is addressed: a round spent on a red build you pushed is a round nobody needed. Re-arm from the printed line, which carries the failure as handled so a standing one does not wake you again.
- **`result=DIRTY`** — a conflict with base. (A terminal block is not reported at this stage: while a review is running, a blocked PR is the ordinary state of a healthy one — one unresolved thread is enough where the repo requires them resolved. It reaches you as `merge=blocked` on the window's `IDLE`, and becomes a reportable stop only under `--merge-stage`, which `references/merge-wait.md` adds once the review is clean.) Surface the cause and ask; don't resolve a conflict autonomously. It prints no re-arm line *on its own*: nothing about that state changes until a human acts, so a watch re-armed on it wakes on it again every tick. Re-spawn once the cause is dealt with. When the same tick also held activity, it arrives as that burst carrying `merge=DIRTY` — handle the round, re-arm, and the bare stop follows on the next tick.

  A PR merely *waiting* for its first review is not this. That is also `BLOCKED` on GitHub, and the watch reports it as nothing at all — which is right, since waiting is what it was armed to do.

- **No `result=` line at all** — the task was killed or failed rather than returning. This is the dangerous one, because it looks exactly like a quiet watch while being its opposite: the watcher stopped observing, and anything pushed or posted since is unreported. **Never treat a missing result as "nothing happened."** Re-read `headRefOid` with `gh pr view` and compare against the SHA you last handled, then re-arm from what GitHub says rather than from what the watcher last told you. Traces make this diagnosable after the fact — see the trace note after the spawn block.

**A result line carrying `verdict_sha=<sha>` is the value to re-arm `--last-verdict` with.** It means the level-triggered check fired — a verdict stands at HEAD that you had not handled. No such field means it didn't fire, so carry the value you already had forward. Re-arming with an empty `--last-verdict=` after handling a verdict that is still at HEAD wakes the next watch instantly and repeatedly, since nothing about that verdict has changed.

The `verdict=<state>` beside it says which verdict that is, so you can tell a clean approval from a findings round before fetching anything. It is a branching hint only — the clean-review path below re-reads the verdict rather than trusting it.

**After pushing a fix in response to feedback, take the `── re-arm ──` line the watch printed and change only the head to the new one** — it is the third argument after the script path. `since` and `--last-verdict` stay as printed: reading the clock for `since` drops whatever the reviewer posted while you were composing the fix, and the old verdict is no longer at HEAD, so carrying it forward cannot wake the watch on it.

⚠️ **The new head is the full 40-character SHA**, from `gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid` — never an abbreviated one you happened to print for a human. The watcher compares it as a string against what GitHub returns, so a short SHA can never match; it refuses one outright (`result=ERROR reason=bad-args`). This is the re-arm's exposure and the spawn's guard does not cover it: that guard tests `$HEAD` for *blankness*, and an abbreviated SHA is not blank. The same holds for `--last-verdict`, which is compared against `commit.oid` the same way — take it from the watcher's `verdict_sha` or from `pr-verdict.sh`, both of which report the full SHA.


