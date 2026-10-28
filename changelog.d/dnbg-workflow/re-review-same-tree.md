A `reviewer` re-review after a rebase that only moved the PR's base, such as
dropping a squash-merged parent's commits, now says the content is unchanged
instead of showing a diff of the new base as if it were the PR's. Re-approving
an unchanged tree is one step rather than a hand comparison in a scratch clone.
