The reviewer now re-posts its verdict whenever new commits land past the SHA its
standing approval is attached to, even when the verdict is unchanged, naming the
SHA in the body. Previously it stayed silent on a change it judged trivial, which
left the approval pointing at an older commit while GitHub's merge box showed an
unqualified green check — and left the author's watcher waiting for a signal the
reviewer had been told not to send.

Both skills now answer "is HEAD approved?" by checking that the latest *verdict*
on the PR is an `APPROVED` attached to `headRefOid` — not by inferring it from the
repo's *Dismiss stale pull request approvals* setting. That setting is meaningless
where no approval is required (the default on a personal repo that gates on CI),
so the inference produced confidently wrong answers in both directions. Where
approvals are required, `reviewDecision` remains the primary source. Nothing in
either skill reads branch protection any more — one less call that needs admin.

`git-workflow` no longer reports a cause for `mergeStateStatus: BLOCKED` without
reading one: an unresolved review thread is now listed alongside a failing check
and a dismissed approval, and it is a hard blocker wherever
`required_conversation_resolution` is on.
