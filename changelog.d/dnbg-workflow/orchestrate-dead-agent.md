`orchestrate` now handles a subagent that ends `failed` on an API or usage-limit
error: the orchestrator resumes it with `SendMessage` once the limit resets, and
dispatches a replacement only when the agent cannot be reached. A replacement
author's prompt names the dead author's worktree and unpushed commits, which the
orchestrator's GitHub reads cannot see, along with the review round it was
answering and any scratch issues or labels it created.
