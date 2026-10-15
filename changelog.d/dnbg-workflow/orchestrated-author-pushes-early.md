An orchestrated author now pushes its branch and opens the draft PR at its
first commit, before the self-review, and pushes after each commit, so an
orchestrator restarted while the author works finds the work on GitHub instead
of starting over. Before, commits made before the self-review were lost to a
restart. The cost is CI running on the earlier pushes; sessions outside
`orchestrate` keep `git-workflow`'s order.

On the same machine, a restarted orchestrator also names the predecessor's
worktree in the author's dispatch prompt, so the fresh author continues there
rather than failing at `git worktree add` on the same branch.

Orchestrators, authors and reviewers now stop their background tasks by id
with the harness's task-stop tool, never with `pkill -f` or a pattern, which
had stopped another agent's watch on the same PR.
