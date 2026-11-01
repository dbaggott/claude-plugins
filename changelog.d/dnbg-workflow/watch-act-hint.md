Every result line from `watch-pr.sh` and `watch-issue.sh` now carries an `act=`
field naming what the result calls for in the role and stage the watch was
armed for, such as `round`, `rearm` or `report`, or `read` where the caller's
reference has to decide.

Agents now read the watch references (`watch.md`, `watch-results.md`,
`issue-mode-wait.md`, `spec-review-wait.md`) and `merge.md` once per session
rather than on every return, wait or re-verdict, and read them again only after
an `ERROR`, a watch that returned no result line, or a context compaction. The
orchestrator reads `triage.md` once, before the first question, and again only
after a compaction.
