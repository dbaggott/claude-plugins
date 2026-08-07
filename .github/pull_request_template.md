<!--
Changelog fragment
------------------
If this PR changes anything a user of a plugin would notice, add a fragment:

    changelog.d/<plugin-name>/<short-slug>.md

The release workflow folds fragments into CHANGELOG.md and the GitHub Release,
then deletes them. **A plugin with no fragments is not released at all** — its
version and tag stay where they are — so a missing fragment means the change
never reaches anyone.

Include a `## Migration` section when a user has to do something (rename a
config key, move a file, change a CLAUDE.md opt-in). That section is published
verbatim in the release notes.

Skip the fragment for changes with no user-visible effect: CI tweaks, typo
fixes in comments, repo meta.

See changelog.d/README.md for the full convention.
-->
