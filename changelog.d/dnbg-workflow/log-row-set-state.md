On a tracking issue, the orchestrator now marks a decision-log row `applied`
with `log-row.sh --set-state`, which changes only that row's State cell and
confirms the write against a concurrent writer, instead of reading the whole
parent body into its context and writing it back by hand.
