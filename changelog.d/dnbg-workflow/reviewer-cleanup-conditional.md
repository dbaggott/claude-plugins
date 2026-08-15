`reviewer`'s end-of-review cleanup is now conditional. A review run entirely
through `gh` creates no checkout, so it no longer opens
`references/worktree.md` at `CLOSED` to be told there is nothing to remove —
that read now fires only when the review actually made a worktree, a clone, or
a scratch directory.
