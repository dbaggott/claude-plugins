`reviewer` now tells the agent how to write batched shell reads that survive
zsh. Where the Bash tool runs zsh, a separator like `echo =====` or a path like
`"$SHA:src/x"` used to abort the whole batch and cost a round trip. Sessions
whose shell is bash are unaffected.
