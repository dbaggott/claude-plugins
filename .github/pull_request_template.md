<!--
Describe the change as it now stands, say what you verified and how, and mention
what you could not check. Under-claiming costs nothing.

Reference issues and PRs by full URL rather than #19.

New here? CONTRIBUTING.md covers scope, the fork flow, and how to run every CI
check locally.

Changelog fragment
------------------
If this PR changes anything a user of a plugin would notice, add a fragment:

    changelog.d/<plugin-name>/<short-slug>.md

Write it as an executive summary for someone who has not read the diff: the new
capability, the bug as they experienced it, or what now costs less. No script
names, no root-cause story, no design argument — those belong in this PR body,
where their reader is. Two or three short paragraphs at most.

The release workflow folds fragments into CHANGELOG.md and the GitHub Release,
then deletes them. **A plugin with no fragments is not released at all** — the
version is Claude Code's update cache key, so without a bump nobody who already
installed the plugin ever receives the change.

CI enforces this: the `lint` job fails any PR touching a plugin directory
without a fragment.

Include a `## Migration` section when a user has to do something (rename a
config key, move a file, change a CLAUDE.md opt-in). That section is published
verbatim in the release notes.

For changes with genuinely no user-visible effect — CI tweaks, typo fixes in
comments — label the PR `no-changelog` instead.

See changelog.d/README.md for the full convention.
-->
