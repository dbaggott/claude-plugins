A new `issue-reviewer` skill reviews an issue **body** — before anyone picks the
issue up — rather than reviewing the work that resolves it. It checks the body
against the tree, judges whether a cold resolver could finish it, and posts a
verdict per issue per round under the reviewer bot until the review converges.
Hand it several issues at once and it also reports what only the set shows: two
issues claiming the same work, one that depends on another scheduled later, work
nobody owns. Answering such a review is covered by `issue-workflow`.

"Review this issue" used to mean only one of these. `reviewer` claimed the
phrasing, so asking for the other silently got you a review of the PRs instead —
or an open-ended wait for PRs that did not exist. Both skills now route on how you
phrase it and ask when it is genuinely ambiguous.

## Migration

The reviewer bot now needs permission to write issues. A newly created one gets
it; a bot you set up earlier does **not**, and reviews of issue bodies cannot post
until you add it — PR reviews are unaffected. Follow **Repair / rotate** in
`reviewer-setup`, and note that a permission added to an App stays pending until
each installation accepts it.
