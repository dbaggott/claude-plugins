# Contributing

Thanks for looking. Nothing here is enforced on you — read what is useful and
ignore the rest.

If you are working with `dnbg-workflow` installed and covered, the skills
already tell your session how this project works, and the hooks keep it honest.
This file is for everyone else: what the project wants, and the handful of
mechanics you cannot guess.

## Whether the gates fire on your fork

Worth knowing so the silence does not mislead you. The two enforcement hooks
only fire for repos in an operator's `owners` config, and `remote_is_covered()`
in [`dnbg-workflow/hooks/lib.sh`](dnbg-workflow/hooks/lib.sh) requires both
`github.com` **and** an owner match. Your fork's owner is you rather than this
project, so unless you have listed your own login in `owners` the gates are
inert on it. That is deliberate — the plugin fails open so a fresh install
blocks nothing — not a sign you have configured something wrong.

List yourself and the opposite holds, which is the ordinary state for anyone
who uses the plugin on their own repos: the fork is covered like any other repo
of yours, and the worktree + draft-PR flow drives your contribution.

## Scope

This is an opinionated single-maintainer project. Knowing where the line sits
should save you writing a PR that gets declined after the work is done.

**Welcome:** bug reports and fixes, tests for untested branches, portability
findings (Windows/Git Bash is expected to work and has never been tested), and
documentation corrections.

**Likely declined:** softening a gate rather than reporting where it misfires,
new always-on rules (that file is charged to every session of every user; a
skill is almost always the right home), and restating an opinion in a second
place.

**The opinions themselves are open, if you make them configurable.** Swapping one
default for another is declined — worktree-then-draft-PR, never merging your own
work, CalVer, fragments-drive-releases are the product rather than incidental
choices, and someone installed this *for* them. But adding a knob that leaves the
current behavior as the default is a different proposal, and a welcome one.
`worktree_path` and `claim_label` are exactly that: opinions that turned out to
be someone else's to make, so they became `userConfig` keys with the original
value as the default.

Two things such a change has to carry. The default has to live somewhere that
*runs* — an unset option substitutes nothing and exports no environment variable,
so the manifest's `default` field is not a fallback; `dnbg-workflow/hooks/lib.sh`
is where the existing ones resolve, and `tests/coupling.bats` pins them against
the manifest. And the skill text has to name the configured value as the default
rather than a constant, the way `.worktrees/` and `assigned:agent-session`
already do, so a session reading it knows the literal may not be what applies.

Either way, an issue first is cheaper than a PR. A short issue costs you minutes;
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

**Sync your fork's `main` before branching** (`gh repo sync <you>/claude-plugins`,
or the Sync fork button). A fork's `main` is a snapshot from whenever you forked
and nothing advances it for you, so branching from a stale one writes the change
against code that has since moved — a conflict at best, a fix for something
already fixed at worst. Nothing warns you: the PR still diffs against the
merge-base, so it looks clean. This is easiest to miss with the fork covered
(above), where `git-workflow` bases the worktree on `origin/<default-branch>`
and on a fork `origin` is the fork.

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

**You can run CI's checks locally.** From the repo root:

```bash
shellcheck $(find . \( -name '*.sh' -o -name '*.bash' \) -not -path './.git/*')
npx --yes bats@1.13.0 tests/
jq empty .claude-plugin/marketplace.json
jq -r '.plugins[].source' .claude-plugin/marketplace.json \
  | xargs -I{} find {} -name '*.json' | xargs -n1 jq empty
claude plugin validate . --strict
actionlint                                  # brew install actionlint
```

Two of those are narrower than the CI step they stand for, so a green run here
is good evidence rather than a guarantee. The `jq` lines are only the JSON-parse
part of the manifest checks, which also compare marketplace and manifest
descriptions and confirm every version is semver-parseable; and
`claude plugin validate .` is the root call, where CI additionally runs it over
each plugin source. Those, and the fragment rule above, are short shell blocks
in the `lint` job of [`.github/workflows/ci.yml`](.github/workflows/ci.yml) if
you want to run the rest by hand.

## More

[`README.md`](README.md) covers what the plugins are and what they do to a
session; [`docs/maintainers.md`](docs/maintainers.md) covers repo layout, where
new content goes, and what a fork inherits from CI, and
[`docs/releases.md`](docs/releases.md) covers versioning.
[`SECURITY.md`](SECURITY.md) covers reporting a vulnerability. The skills under
`dnbg-workflow/skills/` are the philosophy in full — they are the product, so
this file points at them rather than summarizing them.

By contributing you agree your contributions are licensed under
[Apache-2.0](LICENSE), the same as the rest of the repo.
