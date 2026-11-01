# Git workflow: a stacked branch

Part of the `git-workflow` skill. Read this when your prompt names a branch to
stack on, before step 4's calls, including on a worktree or PR you continue. It
changes `SKILL.md`'s steps 4, 7, 8 and 9 where it says, and nothing else.

## Step 4: the base

When your prompt names a branch to stack on, that branch is the base: `origin/<that branch>` stands in for `origin/<default-branch>` in step 4's `git worktree add` and in step 7's ranges. Note `git rev-parse origin/<that branch>` now, as the recorded base head step 8 writes down.

## Step 8: the PR

Add `--base <that branch>` to `gh pr create`, and keep the line `Stacked on <branch> of <PR URL>, recorded base head <sha>.` in the as-built section of each rewrite of the description while the PR stays stacked.

Then put the PR in its base PR's GitHub stack, as the author, with the base PR your prompt's stack line named. In a stack, GitHub rebases the PR itself when its base merges, and one merge lands it with the PRs below it (`references/merge.md`, "A PR in a stack"):

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
  "<skill-dir>/../../scripts/stack-prs.sh" <owner>/<repo> <number> --onto=<base PR number>
```

`result=OK stack=<n>` adds the line `GitHub stack <n>.` under the stacked one, kept in every rewrite of the description for as long as the PR is open: a PR stays in its stack after its base merges, and the stack decides its merge command. Any `result=ERROR` adds nothing, and the PR takes the rebase in `references/merge-wait.md`, "A stacked PR whose base moved", when its base merges. `not-top`, `not-default-base` and `unsupported-forge` are by design: another PR already sits on the base, the base PR's own chain was never stacked, or the forge has no stacks. The rest name a call that failed: say so when you announce the PR, so the operator can have it retried.
