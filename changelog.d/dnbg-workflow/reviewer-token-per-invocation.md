Fixed the `reviewer` skill minting its bot token in a tool call of its own. An
agent harness starts a fresh shell per call, so the token was gone before any
`gh` command spent it and every review posted under the operator's personal
account instead of `agent-reviewer-<owner>[bot]` — silently, since that call
succeeds on a PR the operator did not write. Each posting block now mints the
token alongside the command that uses it, and the review POST prints the
identity it posted under.
