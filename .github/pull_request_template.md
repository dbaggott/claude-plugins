<!--
Writing this description
------------------------
Describe the AS-BUILT state — what the change is now, not the path you took to
it. Every claim has to be true and earned; a reviewer who catches one inflated
claim discounts the whole description, so under-claiming costs nothing and
over-claiming costs trust.

- Name what you verified, and HOW. "shellcheck and `bats tests/` pass" has a
  source; "tested" does not. If you did not run a check, do not phrase the body
  so it reads as if you did.
- Do not assert coverage you do not have, and never describe an intended test as
  an existing one.
- Do not state impact without evidence — back a performance or "fixes it for all
  inputs" claim with the measurement or the reasoning, or hedge it.
- Claim only the scope you checked. That a fix generalizes, that it addresses the
  root cause rather than the symptom you reproduced, that nothing else is
  affected — each is an assumption until verified. Verify it, or state the scope
  you actually covered.
- Surface gaps, not just wins. Known limitations, branches you could not
  exercise, deferred follow-ups. Omitting them reads as "all handled," and the
  next reader inherits the surprise.

Reference issues and PRs by FULL URL (https://github.com/owner/repo/issues/19),
never bare #19 — it is the only form clickable on every surface and unambiguous
when copied between repos. Put the issue URL in the body; use a closing keyword
(`Closes <url>`) only on the PR that actually completes the work.

New to the repo? CONTRIBUTING.md covers scope, the fork flow, and how to run
every CI check locally.

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
