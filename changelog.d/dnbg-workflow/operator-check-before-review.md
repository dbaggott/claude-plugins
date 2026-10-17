Added an operator check before review: an issue can declare, in a
`## Operator check before review` section, that the operator wants to look at the
work before it is polished and reviewed. The author brings the work up from the
recipe in that section once the work is complete, stops with a reachable URL,
takes the operator's feedback round by round, and only on "proceed" runs its
self-review and sends the PR to review. The bot review still runs afterward.

`issue-workflow` asks whether to add the check when an issue's approach touches
anything a person sees or interacts with; an orchestrator records a check the
operator asks for at dispatch time on the issue, so a restart knows whether the
check is still pending, and a headless run posts the recipe and worktree for the
operator to run themselves.
