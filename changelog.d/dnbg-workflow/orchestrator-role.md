`orchestrate` now posts under its own GitHub App: its claims, `Decision log:`
rows, questions, tracking-issue body edits and friction-log relays go through
the new `orchestrator` role, so a watch can tell them from your own comments by
login. Create the App with `reviewer-setup` (`--roles orchestrator`); it needs
only `issues` write and read on `pull_requests` and `metadata`, and no
`contents`.

Until you do, the orchestrator posts as you, exactly as before, and the
session-start notice names it. `log-row.sh` gains `--as=<role>`, whose result
line names the login it wrote as.
