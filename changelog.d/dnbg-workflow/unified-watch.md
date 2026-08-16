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

A check that stops passing is now a wake (`result=CHECKS`), level-triggered like
the verdict.

Under all of it, `fetch-pr-state.sh` and `fetch-issue-state.sh` answer a tick as
one forge-neutral object, so the GitHub-specific parts — the overloaded merge
status, the two check-rollup shapes, the two spellings of a bot login — stay in
one place instead of in each watcher.
