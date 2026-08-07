# claude-plugins

A Claude Code plugin marketplace, published as `dnbg`. It currently hosts one
plugin.

## `dnbg-workflow`

An opinionated GitHub workflow: every change goes through a worktree and a draft
PR, issues are written to survive a cold handoff, and an independent bot identity
reviews the result.

It is a set of **skills** (loaded on demand when they match the task), a short
**always-on rules** file, and two **enforcement hooks** that make the worktree
and issue flows non-optional in the repos you choose.

### It is GitHub-specific

Worth knowing before you install. The workflow skills drive the `gh` CLI
throughout — `gh pr`, `gh issue`, `gh api`, `gh search` — and this isn't
incidental coupling that a shim could paper over:

- `reviewer` and `reviewer-setup` are built on **GitHub Apps**. The entire point
  is an App identity that can post a binding verdict on a PR you authored, which
  GitHub otherwise forbids. GitLab and Bitbucket have no equivalent construct.
- `git-workflow`'s review, merge-state, and auto-merge handling reads
  GitHub-shaped fields (`mergeStateStatus`, `statusCheckRollup`, review threads).
- `check-issue-create.sh` matches `gh issue create`, and `owners` resolves
  against `github.com` remotes.

Two skills are VCS-agnostic and useful anywhere: **`coding-practices`** and
**`prototype-velocity`**. Neither mentions a forge.

One sharp edge if you're on another host: the owner match doesn't inspect the
remote's *host*, so a GitLab remote at `gitlab.com/acme-corp/api` still parses as
owner `acme-corp` and, if you listed it, the worktree gate will fire. The hooks
would work while the skills told you to run `gh` commands that don't apply —
a half-working state that's worse than either extreme. **Leave `owners` empty on
a non-GitHub host** and treat this as a skills-only install.

## Install

```
/plugin marketplace add dbaggott/claude-plugins
```

Then, as a separate command — the install can't run until the marketplace add
completes, and pasting both at once only registers the first as a slash command:

```
/plugin install dnbg-workflow@dnbg
```

> Three names, deliberately different. The **repo** is `claude-plugins` (it
> can host more than one plugin), the **plugin** is `dnbg-workflow`, and the
> **marketplace** is `dnbg` — hence `dnbg-workflow@dnbg`. Claude Code rejects
> marketplace names containing "claude" as impersonating an Anthropic-official
> marketplace, which is why the marketplace needed a name of its own.

The install asks for a scope. Which one you want depends on whether you're
adopting this for **yourself across many repos** or for **one repo shared with
other people** — the two are different problems and the plugin supports both.

### Mode A — one person, many repos

```
/plugin install dnbg-workflow@dnbg --scope user
```

Active in every session on the machine, in any directory. Then set `owners`
(below) to the accounts you want enforced, and the hooks gate every repo under
them without any per-repo setup.

This is the mode the enforcement hooks were built for, and it does something
project scope cannot: the hooks resolve a repo from **the path being edited**,
not from where Claude Code was launched. Working out of a parent directory and
editing files across three repos, the gates still apply correctly to each.

### Mode B — one repo, shared with a team

```
/plugin install dnbg-workflow@dnbg --scope project
```

Writes the plugin into that repo's committed `.claude/settings.json`, so every
collaborator picks it up. Pair it with `extraKnownMarketplaces` in the same file
and teammates get prompted to install it when they trust the folder — the
standard way a repository declares the tooling it expects.

Leave `owners` **empty** in this mode. The skills and rules load for everyone
working in the repo, and the blocking hooks stay inert — which is usually what
you want, because how someone drives their own editor is a personal choice a
repository shouldn't impose on contributors.

(`--scope local` is the same as B but private to you and gitignored — useful for
trying the plugin in a repo without committing anything.)

## Configure which repos it enforces on

**This is what turns the hooks on, and it only matters in Mode A.** At enable
time Claude Code prompts for one value:

| Setting | Meaning |
| --- | --- |
| `owners` | Comma-separated GitHub orgs and/or personal logins — e.g. `acme-corp,yourname` |

A repository is **covered** when its `origin` remote points at one of those
owners. In a covered repo the two hooks below block; everywhere else they do
nothing. Matching ignores case and whitespace, and compares whole names — so
`acme` does not match `acme-corp`.

**Leave it empty and nothing is ever blocked.** The skills still load and still
advise, but no hook halts an edit. That is the deliberate default: a plugin that
can stop your work shouldn't start doing so before you've said where.

To change it later, re-run the plugin's configuration from `/plugin`. The value
is stored in your **user** `settings.json` — and unlike `enabledPlugins`, plugin
config is deliberately *not* read from a project's `.claude/settings.json`, so a
repository you clone can never widen or narrow what gets enforced on your
machine. That asymmetry is also why the opt-in for `prototype-velocity` below
goes through a repo's `CLAUDE.md` rather than through config.

## What it does to your session

Installing this plugin means **it runs shell scripts on your machine** — plugin
hooks execute automatically once a marketplace is trusted. Specifically:

| Hook | When | What it does |
| --- | --- | --- |
| `update-marketplace.sh` | session start | Refreshes this marketplace and plugin, at most once per 4h. Network access to GitHub. |
| `inject-rules.sh` | session start | Prints `always-on-rules.md` into the session's context. |
| `check-worktree.sh` | before every Edit/Write | **Blocks** edits to tracked files in the main checkout of a covered repo. |
| `check-issue-create.sh` | before every Bash | **Blocks** `gh issue create` against a covered repo unless the `issue-workflow` skill is loaded. |

Nothing here sends your code anywhere. Read the five files in
[`dnbg-workflow/hooks/`](dnbg-workflow/hooks/) before you trust them — they are
short, and reviewing code that will run in your own terminal is a reasonable
thing to want.

## What's in it

| Skill | For |
| --- | --- |
| `git-workflow` | Worktree → draft PR → review → merge → cleanup, end to end |
| `issue-workflow` | Writing issues that survive a cold handoff; claiming and resolving one |
| `coding-practices` | Design, security, naming, logging, and the smells to stop on |
| `reviewer` | Reviewing a pushed PR under an independent GitHub App identity |
| `reviewer-setup` | One-time creation of that App (no cloud service, no shared secret) |
| `work-summary` | Turning your merged/open PRs into an audience-shaped recap |
| `prototype-velocity` | Opt-in: how to size work where the risk/benefit trade favors speed |

The `reviewer` pair is the piece with the least in common with the rest — it
exists because GitHub won't let you approve your own PR, and a separate App
identity can. `reviewer-setup` creates that App and keeps its private key on
your machine.

`prototype-velocity` is **opt-in per repo** and off unless a project asks for
it, since it trades away protections most projects need. Whether the trade holds
is a ratio — blast radius, reversibility, how fast breakage is noticed, test
coverage, and users — not a headcount, so a live project with forgiving users and
one-command rollback can sit on the velocity side while a pre-launch one doing an
irreversible migration cannot.

A repo opts in with a short section in its own `CLAUDE.md` naming the posture and
who can unmake it. The skill carries the template.

## Keeping up to date

A session-start hook silently refreshes the marketplace and plugin, at most once
every 4 hours per machine. Because Claude Code loads plugins when a session
*begins*, freshly fetched content applies to the **next** session — so you'll be
on the latest within a session or two of any push, without running anything.

To pull an update immediately, run these one at a time (submit the first, wait,
then the second — pasting both only registers the first):

```
/plugin marketplace update dnbg
```

```
/reload-plugins
```

## For maintainers

```
.claude-plugin/marketplace.json   # the catalog
CHANGELOG.md                      # assembled at release time
changelog.d/<plugin>/             # pending fragments, one per PR
dnbg-workflow/                    # the plugin
  .claude-plugin/plugin.json      # manifest, incl. the `owners` userConfig
  always-on-rules.md              # injected into every session
  hooks/                          # auto-update, rule injection, two gates
  skills/                         # loaded on demand when the description matches
```

Changes go through a PR — never push to `main` directly.

### Changelog fragments

Every PR with a user-visible effect adds a fragment at
`changelog.d/<plugin>/<slug>.md`. The release workflow folds fragments into
`CHANGELOG.md` and the GitHub Release, then deletes them.

Fragments are also what *trigger* a release: a plugin with pending fragments is
released, a plugin without them is not. So a change whose author forgot a
fragment does not ship — nothing breaks, the version simply doesn't move. See
[`changelog.d/README.md`](changelog.d/README.md).

### Versioning

Calendar versioning, `YYYY.M.N` — year, month, and the Nth release of *that
plugin* in that month. Each plugin carries its own counter, so releasing one
doesn't move the others. `.github/workflows/release.yml` computes it
after every merge to `main`, so authors never touch a version in a PR. Run
`claude plugin list` to see what you have installed.

Semver would be fictional here: the plugins ship rules and skills, not an API,
so there is no breaking change to anchor a major bump on. CalVer answers the
only question a consumer actually has — how fresh is this?

The third component is not a semantic, though. Claude Code resolves plugin
dependency version constraints against `{plugin}--v{version}` git tags, and
ignores any tag whose suffix doesn't parse as semver — so a two-component
`YYYY.N` tag would exist and never be selected. Semver also rejects leading
zeros in numeric identifiers, which is why the month is unpadded: `2026.8.1`,
never `2026.08.1`. That costs the columns lining up next to `2026.10.1`, and
nothing else; ordering is numeric and stays correct.

### Installing a specific version

Every release is tagged `{plugin}--v{version}` and published as a GitHub
Release, so a given version is addressable rather than implied. Which version
you end up on depends on whether marketplace auto-update is enabled for `dnbg`
in `/plugin` — with it on you track releases as they land, with it off you stay
on whatever you installed until you update deliberately.

### If you forked this

Nothing in the plugin itself assumes this repo's setup — which repos it enforces
on is the `owners` config, and the skills read a repo's merge settings rather
than assuming them. The **CI** is a different matter, since a fork inherits
`.github/workflows/` verbatim:

- **`ci.yml`** works anywhere. It runs shellcheck and validates the JSON. Whether
  its `ci-required` umbrella actually *blocks* merges is your branch-protection
  setting, not something this repo can decide for you.
- **`release.yml`** needs a GitHub App, because a required status check
  and `GITHUB_TOKEN` are mutually exclusive here (see the comment at the top of
  that file). **It disables itself in a fork** — the job is guarded on an
  `AUTOMATION_APP_ID` variable you won't have, so it skips silently instead of
  failing on a missing credential. Versions stop auto-bumping and you can bump
  `plugin.json` by hand, or wire up your own App and set `AUTOMATION_APP_ID`
  (repository variable) plus `AUTOMATION_APP_PRIVATE_KEY` (repository secret).

If you don't want automated versioning at all, delete that workflow.

### Where new content goes: skill vs always-on vs project CLAUDE.md

Three places content can live; default to the cheapest that fits.

| | Triggers | Cost |
| --- | --- | --- |
| **Skill** (`skills/<name>/SKILL.md`) | when the skill's `description:` matches the task | tokens only when loaded |
| **Always-on rule** (`always-on-rules.md`) | unconditionally, every session, every user | tokens on every session × every user |
| **Project `CLAUDE.md`** (in the consuming repo) | unconditionally, but scoped to that repo | tokens when working in that repo |

- Most guidance is procedural ("how to open a PR", "how we think about
  comments") and can be triggered by a description match — make it a skill.
- Only things that must apply to *every* response and can't be triggered by
  intent ("no flattery") justify always-on. That file is short on purpose.
- Facts about one repo — its layout, its build tool, its conventions — belong in
  that repo's `CLAUDE.md`, not here. The same goes for a stance that isn't
  universally true, which is why `prototype-velocity` is opt-in rather than a
  rule.

If you're tempted to add to `always-on-rules.md`, ask whether a skill
description could fire it instead. If yes, prefer the skill.

## License

[Apache-2.0](LICENSE).
