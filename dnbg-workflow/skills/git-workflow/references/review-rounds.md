# Git workflow: review rounds

Part of the `git-workflow` skill. Read this when the operator sends the PR to
review, before spawning anything. `SKILL.md` carries the flow up to that point;
`references/review-received.md` takes over when a review comes in.

## Watching for the first review

When the operator picks "Send to review" in `SKILL.md`'s picker, or otherwise signals the PR is ready (says "ready", "go", "mark it ready", etc.):

1. Note the time, then run `"<skill-dir>/../../scripts/as-role.sh" author <repo> -- gh pr ready <num> --repo <repo>` if the PR isn't already out of draft. That time is the first arm's `since`, per the first-arm rule in `watch-issue.sh`'s header: the review responds to this step. A PR already out of draft was ready before this step, so its review responds to your last push instead: take `since` from your last commit, `gh pr view <num> --repo <repo> --json commits --jq '.commits[-1].committedDate'`, which is no later than the push.
2. **Record the current head SHA.** Everything else the next arm needs comes back on the watch's own `── re-arm ──` line; this is a first arm, so there is nothing yet to carry.
3. **Spawn `watch-pr.sh`** as a **background** task (Bash `run_in_background: true`, `timeout: 7200000`), and every re-arm of it the same way. Without the timeout a headless session stops the watch after 10 minutes, and it returns no result line. It blocks until something happens, so its idle polling never enters the conversation, and the harness wakes you when it returns.

```bash
HEAD=$(gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid)
# A blank value means the `gh` call above failed. Catch it here rather than
# letting the watcher act on it.
[ -n "$HEAD" ] || { echo "could not resolve head SHA — re-run the watch"; exit 1; }
# --role=author is what makes this an author-side watch: it ignores the author
# role's login, does not wake on any push, reports DIRTY and a terminal block
# because you own the merge, and sizes the window for a wait that should be
# short. The slug is not passed: the watch asks the role resolver for the
# author's login, which is the author App's, or yours when the role falls back.
# So with an author App, your own comments on the PR wake it.
# --last-verdict= is empty here and only here: it says "no verdict handled yet".
# --round-dir is where the watch writes the round it fetches on a wake: your
# draft directory (SKILL.md's "Draft files"), which the re-arm line keeps.
"<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <num> \
  "$HEAD" "<the time you noted in step 1>" "" --role=author --last-verdict= \
  --round-dir=<draft directory>
```

**Re-arm from the line the watch prints, not from the clock.** Every result you
re-arm from is preceded by a `── re-arm ──` line carrying the next invocation
with `since` set to that run's own `now`. Reading the clock instead skips
whatever landed between the run returning and the next one starting, and
activity is counted against `since`, so what falls in that gap is filtered out
for good rather than deferred.

Both watchers trace themselves to `${TMPDIR:-/tmp}/dnbg-watch/<script>-<pid>.log` by default. When a watch returns no result line, that trace says which of three things happened: a `SIGNAL=` line (something stopped it), an `EXIT code=` line (it stopped itself), or a `tick` line and nothing after (an uncatchable kill). It is the only record of why — a killed watch writes no result, and its task output holds at most the `alive` heartbeat lines a running watch prints every minute.

**Do not hand-roll this loop.** It filters your own activity out, settles before reporting so a burst arrives whole, and polls on the SHA you last handled rather than current HEAD — a hand-written version gets each of these wrong in ways that surface as a review silently lost or a stale one reported as fresh. `tests/watch-pr.bats` pins them.

**What each result means is in `references/watch-results.md`.** Read it on the
watch's first return of the session, before branching on what it said, and
again when a result is `ERROR`, when a watch returns no `result=` line, or when
the context has been compacted since. Each result there says whether to re-arm;
`## Re-arming` below says how.

## Re-arming

**A result line carrying `verdict_sha=<sha>` is the value to re-arm `--last-verdict` with.** It means the level-triggered check fired — a verdict stands at HEAD that you had not handled. No such field means it didn't fire, so carry the value you already had forward. Re-arming with an empty `--last-verdict=` after handling a verdict that is still at HEAD wakes the next watch instantly and repeatedly, since nothing about that verdict has changed.

The `verdict=<state>` beside it says which verdict that is, so you can tell a clean approval from a findings round before fetching anything. It is a branching hint only — the clean-review path in `references/review-received.md` re-reads the verdict rather than trusting it.

**After pushing a fix in response to feedback, take the `── re-arm ──` line the watch printed and change only the head to the new one** — it is the third argument after the script path. `since` and `--last-verdict` stay as printed: reading the clock for `since` drops whatever the reviewer posted while you were composing the fix, and the old verdict is no longer at HEAD, so carrying it forward cannot wake the watch on it.

⚠️ **The new head is the full 40-character SHA**, from `gh pr view <num> --repo <repo> --json headRefOid --jq .headRefOid` — never an abbreviated one you happened to print for a human. The watcher compares it as a string against what GitHub returns, so a short SHA can never match; it refuses one outright (`result=ERROR reason=bad-args`). This is the re-arm's exposure and the spawn's guard does not cover it: that guard tests `$HEAD` for *blankness*, and an abbreviated SHA is not blank. The same holds for `--last-verdict`, which is compared against `commit.oid` the same way — take it from the watcher's `verdict_sha` or from `pr-verdict.sh`, both of which report the full SHA.


