Fixed `orchestrate` telling its author to continue an unrelated PR on start or
restart. Every open PR that mentioned the issue was taken for the issue's own
work, including a PR in another repo that only cited it. Now only a PR that
closes the issue, or a multi-repo sibling tagged with its branch name, is handed
to the author; any other is named to you instead, and no longer wakes the
orchestrator's issue watch when it starts.

The PR discovery behind `orchestrate`, `reviewer`'s issue mode and issue pickup
now labels each PR it finds as closing the issue, a tagged sibling, or a mention.
