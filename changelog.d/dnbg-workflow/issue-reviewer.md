A new `issue-reviewer` skill reviews an issue **body** as a spec — before anyone
picks the issue up — rather than reviewing the work that resolves it. It runs a
mechanical pass (unresolvable links, cited anchors that do not exist, markup that
will not render) before a judgment pass, posts one `READY` / `CHANGES REQUESTED`
verdict per issue per round under the reviewer bot, and converges or halts instead
of watching indefinitely. Handed several issues at once, it also reports what only
the set shows: two issues claiming the same work, an issue that depends on one
scheduled later, work the plan implies that nobody owns.

Answering such a review is the author's side of the same protocol, and lives in
`issue-workflow`.

This resolves an ambiguity that used to be silent. "Review this issue" can mean
either review, `reviewer` claimed the phrasing alone, and picking wrong looked
like it was working in both directions — a spec review left the PRs unreviewed, a
resolution review armed an open-ended watch on work nobody had started. Both
skills now route on the phrasing and ask you when it is genuinely ambiguous.

## Migration

The reviewer App now needs permission to write issues. A newly created one gets
it; an App you set up earlier does **not**, because a manifest is only read at
creation — reviews of issue bodies cannot post until you add it. Follow
**Repair / rotate** in `reviewer-setup`, and note that a permission added to an
App stays pending until each installation accepts it. PR reviews are unaffected.
