The PR and merge watchers can now explain their own death, and three ways a watch
could go silently blind are fixed.

**Tracing.** Set `WATCH_LOG=<path>` on either watcher and it records a line per
poll, per signal, and at exit. It is off unless set, and installs nothing when
unset. It exists because a watch that is killed leaves no evidence anywhere else:
its one result line is written at exit, so a killed watch produces an empty output
file, and macOS records ordinary process signals nowhere. Three outcomes separate
the causes, and the third is an absence — a heartbeat with no `SIGNAL` and no
`EXIT` line means SIGKILL or a process-group teardown.

**Behavior change on the shipped path:** a nap is now a backgrounded `sleep` that
is waited on, rather than a foreground one. Bash defers a trap until the running
foreground command finishes, so a foreground nap swallowed a `SIGTERM` for up to a
full interval — five minutes at the cap — and where a `SIGKILL` followed, the
handler never ran at all. This applies whether or not you enable tracing.

Fixes, each of which previously left a watch running and reporting something
plausible but wrong:

- **Replies past the first page of inline comments were invisible.** The comments
  query was unpaginated, and that endpoint caps at 30 and returns oldest-first — so
  on a PR with more than 30 inline comments every new reply landed on a page the
  watch never fetched. It saw only history, never woke, and idled out looking
  healthy. Most likely to bite on a busy PR with several reviewers.
- **A payload that parsed but had lost `.state` passed the shape gate.** An API
  error body is well-formed JSON, so it was accepted with an empty state that
  matched neither MERGED nor CLOSED; the watch ran its whole window against it and
  reported `IDLE` on a PR that had already closed. `isDraft` is now checked too — a
  missing one renders as `null` and silently disabled the draft→ready transition.
- **`INTERVAL=0` was accepted and spun.** Intervals must now be at least 1s
  (offsets may still be 0). A zero interval made each nap return immediately,
  turning the watch into a busy loop around `gh` — measured at 200 naps in 2s,
  enough to exhaust the hourly REST budget in under a minute and leave the watch
  blind behind rate-limit failures for the rest of its window.

Two arguments that used to fail silently now behave: an empty `<last_head>` adopts
the first commit it observes instead of never detecting a push, and an empty
`<bot_slug>` is refused outright instead of leaving the watch waking on its own
posts.
