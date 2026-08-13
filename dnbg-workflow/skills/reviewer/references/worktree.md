# Reviewer: when the review needs a checkout

Part of the `reviewer` skill. Read this only when a specific need for the tree
arrives — `SKILL.md`'s "How to do the work" reads the PR remotely by default, and
most reviews never come here. Both halves live together because a review that
never made a checkout owes neither: creating one, and removing it at `CLOSED`.

## Create a worktree you own

The worktree is **yours** — say that you created it, because you remove it at
`CLOSED` (below):

```bash
git fetch origin pull/<n>/head
git worktree add .worktrees/review-<n> --detach <head-sha>
```

Via the PR ref rather than `origin/<head-branch>`, which doesn't exist for a
fork-based PR. Check out the **head SHA** (from `gh pr view <n> --json
headRefOid`), not `FETCH_HEAD`: `FETCH_HEAD` is per-worktree, so it resolves
only where the fetch ran and is absent in the review worktree you just made.

**`.worktrees/` is the default, not a constant.** It is configurable, so if a
`dnbg-workflow` note at session start names a different worktree root, that
note wins and every `.worktrees/` in this skill means the root it names —
here, and in the cleanup at the end. With no such note, the literal above is
what this session uses.

**This branch is the only part of the skill that needs a local
clone of the target repo** — everything else runs from any directory via
`--repo`, and the remote read above is what keeps that true. Working with no
clone? Read remotely, or clone deliberately and remove it at the end like any
other checkout you created.

## Clean up what you synced, at `CLOSED`

Reviewing can leave a checkout behind
— a worktree made to run a type-checker, a temporary clone, files pulled into a
scratch directory. Remove exactly what *you* created:

```bash
git worktree remove .worktrees/review-<n>   # only if you created it
git worktree prune
```

Two boundaries, and they matter more than the cleanup itself:

- **Never remove anything you didn't create.** The author's worktree and branch
  belong to their side of the flow — `git-workflow`'s post-merge cleanup owns
  those — and other `.worktrees/` entries are other people's in-flight work.
- **Don't delete a shared checkout you merely read from.** Reading files in an
  existing clone creates no cleanup obligation.

A session that quits mid-review leaves its `.worktrees/review-<n>` behind —
expected, not a leak, since re-invoking resumes the watch and still cleans up at
`CLOSED`. Remove it by hand only if the review is being abandoned.

Reviewing entirely through `gh` leaves nothing to remove, which is the normal
case and the reason to prefer it.
