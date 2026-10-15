Fixed `orchestrate` telling its author to continue an unrelated PR on start or
restart. Every open PR that mentioned the issue was taken for the issue's own
work, including a PR in another repo that only cited it. Now only a PR that
closes the issue, or a multi-repo sibling tagged with the closing PR's branch
name, is handed to the author; any other is named to you instead. PRs found at
start no longer wake the orchestrator's issue watch the moment it is armed.
