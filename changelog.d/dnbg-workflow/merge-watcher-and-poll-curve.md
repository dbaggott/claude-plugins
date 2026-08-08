Both background watchers now measure time in **laptop-open seconds** and share
one poll curve.

- **A suspended machine no longer burns a watch.** Closing the lid overnight used
  to retire the merge watcher's whole window, so it woke to an already-blown
  deadline and reported "watched the full window, no merge" having never once
  looked. Suspended time is now discounted from both the window and the poll
  interval, and a watch comes back at the 10-second floor — fastest at exactly
  the moment you have reopened the machine.
- **New poll curve, shared by every watch** (merge, first review, PR-appears):
  10s at the start, easing to 30s over half an hour, a minute by the 90-minute
  mark, then 5 minutes flat. Whatever you are waiting for usually happens in the
  first few minutes and nearly always within the hour, so the wait is short when
  it matters and cheap when it doesn't. Tunable via `POLL_CURVE`.
- **The merge watcher is a real script** (`scripts/watch-merge.sh`) rather than
  51 lines of shell inlined in `git-workflow`'s prose, so `shellcheck` covers it
  and `tests/watch-merge.bats` pins every branch — including a payload that
  stops parsing, and a blocked-but-still-running check, neither of which had any
  coverage before.
- **It reports a `result=` line for every outcome**, where the inline version
  printed one only for timeouts and total failures and left the caller to infer
  the rest from state fields. `result=UNREACHABLE` is replaced by
  `result=ERROR reason=<source>`, which trips as soon as a source has failed
  repeatedly instead of burning the entire window first.
