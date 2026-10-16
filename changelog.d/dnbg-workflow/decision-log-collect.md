`orchestrate` no longer has a session working one child of a tracking issue
write the parent's decision-log table, which the parent's orchestrator alone
edits. That session now writes only the `Decision log:` comment on the child,
and the parent's orchestrator collects those comments into its table on start,
when a child closes, and before the closeout folds the log into the design.
