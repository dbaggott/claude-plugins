# Git workflow: watch results

Part of the `git-workflow` skill. Read this whenever an author-side
`watch-pr.sh` returns, before branching on what it said.
`references/review-rounds.md` starts the watch and says how to re-arm from its
`── re-arm ──` line. At the merge stage, `references/merge-wait.md` governs
re-arming, `IDLE`, `DIRTY` and `BLOCKED cause=terminal`; the other entries here
apply there too.

## Branch on `result=`

After any `alive` heartbeat lines, the script prints a summary of the activity it saw as one JSON object per line — who posted what kind of thing, where, without the text — then, on the results with a round behind them, a `── next ──` line carrying the `pr-round.sh` call that reads that round in full, then one result line. Treat the returns differently:

- **`result=ACTIVITY`** — a review, comment or reply landed. Go to `references/review-received.md`.
- **`result=COMMITS`** — someone pushed to the branch. **Reviewer role only**: this role cannot tell your push from anyone else's, so it reports none of them rather than waking you on your own. A third party's push is not lost by that — it is not *announced*, but the head the re-arm carries does not advance past it, so the next round's `── next ──` diff still spans it. A reviewer who pushes *and* comments does wake you, as `ACTIVITY`, and that diff covers the push too.
- **`activity=1` on any burst** — comments or replies landed alongside whatever the result names. **Handle them in this same pass**, per `references/review-received.md`. Ignoring the flag is *permanent* loss, not deferral — you re-arm with `since` set to now, so anything unread is filtered out for good. `activity=0` means the burst was something else (a verdict, a check), so there is no conversation to go looking for.
- **`result=CLOSED`** — merged or closed. Stop watching; if `state=MERGED`, run the post-merge cleanup in `references/post-merge.md`.
- **`result=ERROR reason=<source>`** — the watch itself is broken: that source failed repeatedly, so it cannot see. **Do not re-arm** — you would poll straight back into the same failure. Check `gh auth status` and the `<num>`/`<repo>` pair, then tell the operator. Unlike `IDLE` this means nothing about the PR; the watch never got a look at it.
- **`result=ERROR reason=bad-args`** — the watch refused to start because an argument could not do its job. Usually a re-arm's argument: an abbreviated `<last_head>` or `--last-verdict` value (see the full-SHA note in `references/review-rounds.md` — both take a full 40-character SHA), a missing `--role`, or a trailing flag outside the accepted set. Fix it and re-spawn.
- **`result=ERROR reason=role`** — the watch asked the role resolver for the author's login (`as-role.sh --login author <repo>`) and was refused; the resolver's reason is on stderr. `operator-auth` is your own `gh` auth, when the author falls back; the others (`no-login`, `shared-identity`, …) are the author App's configuration. Fix that, then re-spawn.
- **`result=IDLE`** — the window elapsed with nothing. **At the review stage this means something is probably wrong** — a reviewer that never replied, or the wrong `<num>`/`<repo>`. Wake once and tell the operator; do **not** silently re-arm. (The reviewer role treats `IDLE` as routine, which is why the role is an argument rather than a caller convention.)

  **An `IDLE` carrying `window_left=` is not this.** A run also ends at a wall-clock ceiling, which a long suspend reaches with most of the window unspent. Re-arm from its line, and neither report it nor count it.

  **Check whether HEAD is already approved before reporting that no review landed** — run `pr-verdict.sh` per `SKILL.md`'s "Know the repo's merge settings". If it is `APPROVED` at HEAD, the review is *in hand* and the watch simply missed it. Reporting "no review has landed" over a standing approval is a false statement about the PR, made from the watcher's blind spot rather than from the PR. If HEAD is not approved, the entry above stands.

- **`result=CHECKS checks='<names>'`** — a check on the watched head stopped passing. Read it before telling the reviewer a finding is addressed: a round spent on a red build you pushed is a round nobody needed. Re-arm from the printed line, which carries the failure as handled so a standing one does not wake you again. `failed_tests='<names>'` rides along when the job log names them in `not ok` lines; without it, `gh api --allow-escape-sequences repos/<owner>/<repo>/actions/jobs/<job-id>/logs` reads the log, which `gh run view --log-failed` refuses while other jobs run.

  **A failure in a test the diff doesn't touch gets one rerun before anything else.** It touches the test when it changes the test, or anything the test loads or runs. Take the run id from the check's link in `gh pr checks <num> --repo <repo>`, run `gh run rerun <run-id> --failed --repo <repo>`, and wait on it with a background `gh run watch <run-id> --exit-status --repo <repo>`: the PR watch says nothing when a rerun passes, so its silence cannot tell you the outcome. A repeat failure can also wake the PR watch as `CHECKS`; that is the same event, not a second one, and gets no second rerun.
  - **The rerun passes**: it was a flake. Leave the PR as it is, and name the test and both attempts' URLs under Actionable in your next report.
  - **It fails again on the same head**: don't presume a flake, since the diff may have changed timing somewhere the test reaches. Investigate it as you would a finding.
- **`result=DIRTY`** — a conflict with base. (A terminal block is not reported at this stage: while a review is running, a blocked PR is the ordinary state of a healthy one — one unresolved thread is enough where the repo requires them resolved. It reaches you as `merge=blocked` on the window's `IDLE`, and becomes a reportable stop only under `--merge-stage`, which `references/merge-wait.md` adds once the review is clean.) Surface the cause and ask; don't resolve a conflict autonomously. It prints no re-arm line *on its own*: nothing about that state changes until a human acts, so a watch re-armed on it wakes on it again every tick. Re-spawn once the cause is dealt with. When the same tick also held activity, it arrives as that burst carrying `merge=DIRTY` — handle the round, re-arm, and the bare stop follows on the next tick.

  A PR merely *waiting* for its first review is not this. That is also `BLOCKED` on GitHub, and the watch reports it as nothing at all — which is right, since waiting is what it was armed to do.

- **No `result=` line at all** — the task was killed or failed rather than returning. This is the dangerous one, because it looks exactly like a quiet watch while being its opposite: the watcher stopped observing, and anything pushed or posted since is unreported. **Never treat a missing result as "nothing happened."** Re-read `headRefOid` with `gh pr view` and compare against the SHA you last handled, then re-arm from what GitHub says rather than from what the watcher last told you. Traces make this diagnosable after the fact — see the trace note after the spawn block in `references/review-rounds.md`.
