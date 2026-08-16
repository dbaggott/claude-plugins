Watching a PR is now one arming from open through merge, and issues can be
watched for conversation rather than only for a PR appearing.

`watch-pr.sh` takes `--role=author|reviewer`, which decides whose activity to
ignore, whether a push is news, whether merge state is a wake, and the window —
all of which were previously the caller's to get right. It reports the
conflict and terminal-block results `watch-merge.sh` used to own, so there is no
second watcher to swap to. **`watch-merge.sh` is removed**; callers of it want
`watch-pr.sh --role=author`.

That swap is what this fixes: a reviewer posting findings *after* approving
landed in the window between the two watchers and was never reported.

Every result a caller re-arms from now carries a `── re-arm ──` line with the
next invocation filled in, `since` set to the finishing run's own `now`. A caller
reading the clock instead skipped whatever landed in between, and activity is
counted against `since`, so it was filtered out for good rather than deferred.

`watch-issue.sh` is new: it wakes on a comment, a body edit, a linked PR
appearing, or the issue closing, across any number of issues for one call per
tick. `watch-pr.sh --issue`, which polled only for a linked PR, is removed in
its favour.

A check that stops passing is now a wake (`result=CHECKS checks='<names>'`),
level-triggered like the verdict. Names are shell-quoted, since a default matrix
job is called `build (macos-latest)` and an unquoted name makes the re-arm line
a syntax error rather than a command.

`DIRTY` and a terminal block print no re-arm line, joining `CLOSED` and `ERROR`:
none of the four clears without a human, so re-arming on one wakes on it again
every tick. A PR merely waiting for its first review is no longer read as a
terminal block — GitHub reports that as `BLOCKED` too, which would have ended
every author-side watch on its first tick on any repo that requires an approval.

An issue closing no longer drops activity still settling on the other watched
issues — both ride one line, the closure as `closed=`. Previously the closure
won and the re-arm set `since` past the activity, losing it for good.

Under all of it, `fetch-pr-state.sh` and `fetch-issue-state.sh` answer a tick as
one forge-neutral object, so the GitHub-specific parts — the overloaded merge
status, the two check-rollup shapes, the two spellings of a bot login — stay in
one place instead of in each watcher.
