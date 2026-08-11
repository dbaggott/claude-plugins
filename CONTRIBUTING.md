# Contributing

Thanks for looking. This repo is unusual in one way that is worth knowing before
you spend any effort on it: **the workflow it publishes is the workflow it uses,
but it cannot make you use it.**

The `dnbg-workflow` plugin ships two `PreToolUse` hooks that gate edits and
issue creation. They fire only for repos listed in an operator's `owners`
config, and `remote_is_covered()` in
[`dnbg-workflow/hooks/lib.sh`](dnbg-workflow/hooks/lib.sh) requires **both** the
remote's host to be `github.com` **and** its owner segment to appear in that
list. Your fork's `origin` is `github.com/<you>/claude-plugins`, and `<you>` is
not in the maintainer's list — so on a fork the gates are silently inert. That is
correct behavior, not a bug: the plugin deliberately fails open so a fresh
install blocks nothing.

The consequence for you is that the discipline described below is on you to
apply, with nothing enforcing it. That is why it is written down here.

## Scope: what is welcome, and what is not

This is an opinionated single-maintainer project. Knowing where the line sits
should save you from writing a PR that gets declined after the work is done.

**Welcome:**

- **Bugs.** A hook that fires on a repo it should not touch, a watcher that
  misreads a state, a skill instruction that contradicts observed `gh` behavior.
- **Tests.** `tests/` is bats over the real interface — a JSON payload on stdin,
  an exit code out. Coverage for an untested branch is welcome on its own.
- **Portability.** The hooks target macOS and Linux; Windows/Git Bash is
  expected to work and has never been tested. Evidence either way is useful.
- **Docs.** Corrections, clarifications, and anything that makes the repo
  legible to someone who has not read the whole thing.
- **Forge support.** The workflow skills are GitHub-only by design and decline
  cleanly elsewhere. Extending that is a large, coordinated change — open an
  issue before writing code.

**Likely to be declined:**

- **Changes to the opinions themselves.** Worktree-then-draft-PR, never merging
  your own work, CalVer, fragments-drive-releases, the self-documenting issue
  body — these are the product, not incidental choices. A PR arguing for a
  different opinion is a discussion, and the issue tracker is where it belongs.
- **Softening a gate.** The hooks are meant to be satisfied, not routed around.
  If one blocks a case it should not, that is a bug report with a repro, not a
  reason to widen the escape hatch.
- **New always-on rules.** That file is charged to every session and every
  subagent of every user. See [Where new content
  goes](README.md#where-new-content-goes-skill-vs-always-on-vs-project-claudemd)
  — almost everything belongs in a skill instead.
- **Restating a skill somewhere else.** Two copies of an opinion is two things
  to keep true.

When in doubt, file an issue first. A short issue costs you minutes; a declined
PR costs you the whole change.

## The flow

You do not have push access, so this is the ordinary fork flow:

1. Fork the repo and clone your fork.
2. Branch from `main`. One logical change per branch.
3. Make the change, add or update tests, add a changelog fragment if a plugin
   directory changed (see below).
4. Run the checks locally (see below).
5. Push and open a **pull request against `dbaggott/claude-plugins:main`**.

Open it as a draft if it is not finished — a draft signals "not yet asking for
your attention," which is exactly what it is for. CI runs when a PR is marked
ready for review rather than on every draft push.

Do not merge your own PR, and do not force-push over a review in progress
without saying so in the thread.

## Running the checks locally

Everything CI gates on can be run before you push. `ci-required` in
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) is the umbrella; these are
its parts.

**Shell — every `.sh` file.** Configuration lives in `.shellcheckrc`, so run it
from the repo root or `source=` directives will not resolve.

```bash
shellcheck $(find . -name '*.sh' -not -path './.git/*')
```

**Hook and watcher tests.** bats, pinned to the version CI runs.

```bash
npx --yes bats@1.13.0 tests/
```

**JSON manifests parse.** The file list derives from the marketplace, so adding
a plugin needs no edit here.

```bash
jq empty .claude-plugin/marketplace.json
jq -r '.plugins[].source' .claude-plugin/marketplace.json \
  | xargs -I{} find {} -name '*.json' | xargs -n1 jq empty
```

**Manifests are valid, not merely parseable.** Catches unrecognized fields and
version disagreements that `jq empty` cannot see.

```bash
claude plugin validate . --strict
```

**Workflow files.** CI runs a pinned `rhysd/actionlint` Docker image; locally
the binary is easier.

```bash
brew install actionlint   # or see the actionlint README for your platform
actionlint
```

CI additionally checks that each marketplace description matches its plugin
manifest, that every version is semver-parseable, and that a changed plugin
carries a changelog fragment. Those three are short shell blocks inside
`ci.yml` if you want to run them by hand; the fragment rule is the one you are
most likely to trip, and it is covered next.

## Changelog fragments

**If your change touches a plugin directory, it needs a fragment.** This is a
hard CI gate, and the reason is not release notes:

> A plugin's version is Claude Code's update cache key. No fragment means the
> release workflow does not bump that plugin, which means nobody who already
> installed it ever receives your change.

The failure is silent and can sit for months. Add a file at
`changelog.d/<plugin-name>/<short-slug>.md` written for someone reading release
notes, with a `## Migration` section if a user has to act. The full convention
is in [`changelog.d/README.md`](changelog.d/README.md).

For a change with genuinely no user-visible effect, the maintainer can apply the
`no-changelog` label — say in your PR description that you believe it applies
and why, since you cannot set labels on a fork.

## What a good PR looks like here

The bar the project holds itself to is in the `git-workflow` skill's "Writing
the PR description" section, and it applies to outside PRs too. The short form:

- **Describe the as-built state, not the development history.** What the change
  is now, not the path you took to it.
- **Name what you verified, and how.** "shellcheck and `bats tests/` pass" is a
  claim with a source. "Tested" is not. If you did not run something, do not
  phrase the body so it reads as if you did.
- **Surface gaps, not just wins.** Known limitations, branches you could not
  exercise, follow-ups you are deliberately deferring. Omitting them reads as
  "all handled," and the reviewer inherits the surprise.
- **Reference issues and PRs by full URL** — `https://github.com/owner/repo/issues/19`,
  never bare `#19`. Full URLs are the only form clickable on every surface and
  unambiguous when copied between repos.

A description a reviewer can trust line-for-line is worth more than an
impressive one they have to second-guess.

## Filing an issue

Issue templates live in [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) and
pre-seed the structure this project expects: the problem, a proposed approach
with anchors you actually checked, open questions stated as decisions-with-
defaults, and acceptance criteria that can be run against the merge commit of
that issue alone.

Two labeling axes, and an issue carries one from each:

- **Type** — exactly one of `bug`, `enhancement`, `documentation`.
- **Area** — at least one `area:*` label. The set is per-repo and self-
  describing; list it with `gh label list --repo dbaggott/claude-plugins --search area`
  rather than working from a copy that can go stale.

Contributors cannot set labels on a new issue, so the templates pre-apply the
type label and ask you to name the area in the body. The maintainer applies it.

Two things the templates do **not** cover, so that you are not surprised:

- **The web UI is where they fire.** A non-interactive `gh issue create --body …`
  supplies its own body and never sees a template. That path is covered instead
  by the `check-issue-create.sh` hook, which blocks the command until the
  `issue-workflow` skill has been loaded — and, as above, only for a covered
  repo.
- **Blank issues are still allowed.** A half-formed report is better than no
  report. The templates are guidance, not a gate.

## Where to read more

This file covers the mechanics of contributing. It does not restate the
philosophy, which lives in the skills themselves — they are the product, and a
second copy would be a second thing to keep true.

- [`README.md`](README.md) — what the plugins are, how to install them, what
  they do to a session. The [For
  maintainers](README.md#for-maintainers) section covers repo layout,
  versioning, and what a fork inherits from CI.
- [`dnbg-workflow/skills/git-workflow/SKILL.md`](dnbg-workflow/skills/git-workflow/SKILL.md)
  — the worktree/PR/review/merge flow in full.
- [`dnbg-workflow/skills/issue-workflow/SKILL.md`](dnbg-workflow/skills/issue-workflow/SKILL.md)
  — why issue bodies are shaped the way they are.
- [`dnbg-practices/skills/coding-practices/SKILL.md`](dnbg-practices/skills/coding-practices/SKILL.md)
  — the code and comment bar applied in review.
- [`SECURITY.md`](SECURITY.md) — reporting a vulnerability, and the threat model
  for what installing actually grants.

## License

By contributing you agree that your contributions are licensed under
[Apache-2.0](LICENSE), the same as the rest of the repo.
