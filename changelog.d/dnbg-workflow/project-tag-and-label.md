A tracking issue and its children now carry two visible handles for the
project they belong to: a `[<slug>]` title tag, chosen when the tracking issue
is filed and written into every child's title at decomposition, and a
`project:<slug>` label that the decomposition procedure mints and applies.
GitHub's sub-issue link shows only on issue pages; the tag reaches issue lists,
search, notification subjects and PR titles, and the label is what to filter on.

`git-workflow` puts the same tag on a PR that resolves a tagged issue, and
`issue-reviewer`'s set review reports a child missing the tag or the label.
