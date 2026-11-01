# Issue workflow: waiting for the next spec-review round

Part of the `issue-workflow` skill. Read this the first time in the session that
`references/spec-review-rounds.md` sends you to wait for a round, which is any
wait not on a spawned reviewer's report, and act on that copy at later waits.
Read it again when a result is `ERROR`, when a watch returns no `result=` line,
or when the context has been compacted since you read it. `<skill-dir>` is this
skill's Base directory.

Spawn the wait as a **background** task with `timeout: 7200000`, and every
re-arm of it the same way, so idle polling never enters the conversation.
Without the timeout a headless session stops the watch after 10 minutes, and it
returns no result line. Its `--since` follows the first-arm rule in
`watch-issue.sh`'s header,
taking the response's own timestamp from GitHub
(`gh api repos/<owner>/<repo>/issues/comments/<id> --jq .created_at`, the id
from the URL `gh issue comment` printed):

```bash
"<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <n> [n...] \
  --role=author --since=<your response comment's created_at>
```

With no `--slug`, `--role=author` asks the role resolver for the login to ignore:
the author App's, or yours when the author has no App. So the watch ignores the
author's own comments and wakes on the reviewer's, and on yours too when the
author has an App. Arm it
*after* posting the response. The first-arm rule's time is the comment's own,
not your clock's, because a body edit carries no login to filter: a `since`
before your last edit by GitHub's clock wakes the watch on your own round.

Every result line carries `act=`, the branch below that its result takes for
the author:

| `act=` | Results | What to do |
|---|---|---|
| `round` | `ACTIVITY` with `comment` in `kinds=` | Read the round. |
| `stop` | `CLOSED` | Stop. |
| `count` | `IDLE` with no `window_left=` | Count the empty window and re-arm from the printed line; tell the operator after the second. |
| `rearm` | `IDLE` with `window_left=` | Re-arm from the printed line, without counting it. |
| `read` | `ERROR`, any other `ACTIVITY`, and any result with `missing=` or `closed=` | `ERROR` takes its entry below. For the rest, read the issues before acting, and say which issues a `missing=` or `closed=` names. |

Dispatch on the result:

- **`ACTIVITY`** with `kinds=comment` — the next round landed. Read it.
- **`CLOSED`** — the issue closed rather than converging. Stop.
- **`IDLE`** — the deadline elapsed. Re-arm; after a second empty window, tell the
  operator nothing has landed rather than waiting silently. An `IDLE` carrying
  `window_left=` is a run cut short at the watch's wall-clock ceiling, not an
  empty window: re-arm and don't count it.
- **`ERROR`** — the watch could not see the issue, whatever the reason. **Do not
  re-arm**, and do not report that the reviewer has not answered: you do not know
  that. `reason=issue-query` points at auth or the issue numbers;
  `issue-query-shape` means the payload stopped parsing, so auth will look fine;
  `bad-args` and `unsupported-forge` mean it never started, and `role` that the
  resolver refused the author's login, with why on stderr.

**Re-arm from the `── re-arm ──` line the watch prints, never from the clock.** It
carries `since` set to that run's own `now`; activity is counted against `since`,
so anything landing between one run returning and the next starting is filtered
out for good rather than deferred.

**A dead watch is not a quiet review.** The watch lives in this session, so a
background task returning no result line at all — killed, session ended, reloaded
— is blindness rather than silence, and looks identical to a round nobody has
posted. Re-read the issues' comments before concluding the reviewer has gone quiet.
