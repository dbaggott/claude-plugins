Follow-ups to the watcher tracing, all from review of the change that added it.

- **`git-workflow` now handles a watcher that returns nothing.** Both of its watch
  loops — the review watch and the merge watch — had no branch for a missing
  `result=` line, so a killed watcher was indistinguishable from a quiet one. That
  matters most on the merge watch, which runs for hours while you are away: a kill
  there could swallow the merge and skip the post-merge cleanup entirely. Both now
  say to re-read the PR's real state rather than trusting the watcher's silence,
  and the spawn instructions point at the trace file that says which of the three
  deaths occurred. `reviewer` already had this branch; the two are now consistent.
- **A watcher's trace now records its own arguments.** `START` named only the
  script and pid, so a stray trace showed that *a* watch had died but not which PR
  it was watching — the one thing a post-mortem across several kills needs.
- **The bats reaper verifies a process is still ours before killing it.** It fires
  at pids that are routinely already dead, and `kill` on a corpse is a harmless
  no-op only until the number is recycled — after which it kills a stranger,
  possibly in another session. Reuse is not plausible at observed pid churn, but
  the guard costs one `ps` and removes the failure mode rather than resting on
  that arithmetic.
