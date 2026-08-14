Split `git-workflow`'s `SKILL.md` along the workflow timeline, the way `reviewer`
was split. The file now carries the path a change actually walks — check the
forge, worktree, edit, commit, self-review, push, draft PR, send to review — and
hands off at the point each reference binds: `references/review-rounds.md` when
the operator sends the PR to review, and `references/merge.md` once a review
comes back clean.

The skill drops from about 10,000 words to 3,100. Neither reference is reachable
until a PR is open and reviewed, so a session that opens a draft and stops there
no longer loads them.

Post-merge cleanup travels with the merge rather than staying behind: on the
timeline it binds after the merge, not during the opening flow. `SKILL.md` names
`references/merge.md` for the cold case — a session told a PR merged that never
handled a round.
