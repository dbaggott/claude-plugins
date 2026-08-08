The PR/issue watcher no longer reports a broken watch as a quiet one. If a poll
source fails repeatedly it emits `result=ERROR reason=<source>`, and both skills
now stop and tell you to check `gh auth status` rather than re-arming into the
same failure forever. Previously a watch that never once reached GitHub ran out
its window and printed the same `result=IDLE` a genuinely calm PR prints.

A second, quieter version of the same bug is fixed too: the thread-replies query
ended in `|| echo 0`, so a failure read as "no new replies" while the main poll
kept succeeding — the watch looked healthy and was partly blind.

Polling is now a curve rather than a fixed 30s. It starts at 10s so a reply lands
almost immediately, holds 30s for an hour after the last activity, then backs off
to 15 minutes once nothing is happening. A 6-hour watch drops from roughly 1440
API calls to about 294, while the first minute gets faster.

The reviewer's issue-scoped wait — used when one agent implements an issue and
another reviews it — now runs on the same script in `--issue` mode instead of its
own fixed two-minute loop, so it gets the curve and the failure reporting too.
