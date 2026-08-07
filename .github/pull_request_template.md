<!--
Changelog fragment
------------------
If this PR changes anything a user of a plugin would notice, add a fragment:

    changelog.d/<plugin-name>/<short-slug>.md

The release workflow folds fragments into CHANGELOG.md and the GitHub Release,
then deletes them. **A plugin with no fragments is not released at all** — the
version is Claude Code's update cache key, so without a bump nobody who already
installed the plugin ever receives the change.

CI enforces this: `changelog-fragment` fails any PR touching a plugin directory
without a fragment.

Include a `## Migration` section when a user has to do something (rename a
config key, move a file, change a CLAUDE.md opt-in). That section is published
verbatim in the release notes.

For changes with genuinely no user-visible effect — CI tweaks, typo fixes in
comments — label the PR `no-changelog` instead.

See changelog.d/README.md for the full convention.
-->
