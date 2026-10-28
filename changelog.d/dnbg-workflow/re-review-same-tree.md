A `reviewer` re-review after a rebase that only moved the PR's base, such as
dropping a squash-merged parent's commits, now recognises that the reviewed
content is unchanged instead of showing the new base's changes as if they were
the PR's. What is left before re-approving is a read of the PR's own diff against
its new base for any change it would revert, rather than a hand comparison in a
scratch clone.
