Closed two ways `reviewer` silently lost events when re-arming a watch. Both
looked exactly like a quiet PR, which is what made them worth stating.

**Re-arming with a self-generated timestamp opened a blind window.**
`references/watch.md` said to carry the `now` the watcher reported but never said
why, so a fresh `date -u` read as an equivalent source of it — and the interval
between the two readings is observed by no watch. The step now carries the reason
and names what survives a gap: commits and verdicts do, being level-triggered by
head SHA and `--last-verdict`; comments, replies and `COMMENTED` reviews are
counted against `since_iso` and are dropped for good. `SKILL.md`'s record-state
step, which previously named `date -u` unqualified, now scopes it to the first
arm.

**Nothing said the issue-scoped wait is a singleton.** `references/issue-mode.md`
told the reviewer to re-discover on every watcher return, which could be read as
arming a *second* issue wait alongside the one already running — each paginating
the whole timeline every tick, both reporting the same `CLOSED`. It now states
that at most one exists at a time, re-armed only on its own return, and that an
armed issue wait *is* the discovery mechanism, so a PR watcher's return need only
handle its own PR. Discovery stays unconditional with no issue wait armed, at any
`CLOSED`, and on the issue wait's own `ACTIVITY`.
