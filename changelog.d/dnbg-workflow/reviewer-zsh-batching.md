`reviewer` now tells the agent how to write batched shell reads that survive
zsh, the login shell the Bash tool often runs. A separator like `echo =====`
used to abort the whole batch there, costing a round trip on a large share of
reviews.
