# Contributing

Thanks for looking. Nothing here is enforced on you — read what is useful and
ignore the rest.

If you are working with `dnbg-workflow` installed and covered, the skills
already tell your session how this project works, and the hooks keep it honest.
This file is for everyone else: what the project wants, and the handful of
mechanics you cannot guess.

## The gates do not fire on your fork

Worth knowing so the silence does not mislead you. The two enforcement hooks
only fire for repos in an operator's `owners` config, and `remote_is_covered()`
in [`dnbg-workflow/hooks/lib.sh`](dnbg-workflow/hooks/lib.sh) requires both
`github.com` **and** an owner match. Your fork's owner is you, so on it the
gates are inert. That is deliberate — the plugin fails open so a fresh install
blocks nothing — not a sign you have configured something wrong.

## Scope

This is an opinionated single-maintainer project. Knowing where the line sits
should save you writing a PR that gets declined after the work is done.

**Welcome:** bug reports and fixes, tests for untested branches, portability
findings (Windows/Git Bash is expected to work and has never been tested), and
documentation corrections.

**Likely declined:** changes to the opinions themselves — worktree-then-draft-PR,
never merging your own work, CalVer, fragments-drive-releases — since those are
the product rather than incidental choices. Also: softening a gate rather than
reporting where it misfires, new always-on rules (that file is charged to every
session of every user; a skill is almost always the right home), and restating
an opinion in a second place.

Those are discussions worth having in an issue. A short issue costs you minutes;
a declined PR costs you the whole change.

## Filing an issue

Say what happened, where, and what you expected. That is genuinely enough — if
it needs more, it will be asked for.

Templates exist for the three types and pre-apply the type label; they are a
convenience, not a form to complete. Delete whatever does not apply, or start
from a blank issue.

The maintainer applies an `area:*` label. If you know which subsystem it is,
mention it — `gh label list --repo dbaggott/claude-plugins --search area` lists
the current set.

## Opening a PR

The ordinary fork flow: fork, branch from `main`, one logical change, push, and
open a PR against `dbaggott/claude-plugins:main`. Draft it if it is not
finished. Do not merge your own PR.

For the description, the only thing asked is that it be accurate: say what you
verified and how, and mention what you could not check. Under-claiming costs
nothing. The full version is `git-workflow`'s "Writing the PR description", if
you want it.

Reference issues and PRs by full URL rather than `#19` — it is the only form
that stays clickable and unambiguous when copied between surfaces.

## Two mechanics you cannot guess

**A change under a plugin directory needs a changelog fragment.** This one is a
CI gate, and not for the reason you would assume: a plugin's version is Claude
Code's update cache key, so no fragment means no version bump, which means
nobody who already installed the plugin ever receives your change. The failure
is silent and can sit for months. Add
`changelog.d/<plugin-name>/<short-slug>.md`; see
[`changelog.d/README.md`](changelog.d/README.md). If you believe your change has
no user-visible effect, say so in the PR and the `no-changelog` label can be
applied — you cannot set labels from a fork.

**Everything CI checks, you can run locally.** From the repo root:

```bash
shellcheck $(find . -name '*.sh' -not -path './.git/*')
npx --yes bats@1.13.0 tests/
jq empty .claude-plugin/marketplace.json
claude plugin validate . --strict
actionlint                                  # brew install actionlint
```

CI additionally checks that marketplace and manifest descriptions match, that
versions are semver-parseable, and the fragment rule above. Those are short
shell blocks in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## More

[`README.md`](README.md) covers what the plugins are and what they do to a
session; its [For maintainers](README.md#for-maintainers) section covers repo
layout, versioning, and what a fork inherits from CI.
[`SECURITY.md`](SECURITY.md) covers reporting a vulnerability. The skills under
`dnbg-workflow/skills/` are the philosophy in full — they are the product, so
this file points at them rather than summarizing them.

By contributing you agree your contributions are licensed under
[Apache-2.0](LICENSE), the same as the rest of the repo.
