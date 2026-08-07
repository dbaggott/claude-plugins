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

## Install

```
/plugin marketplace add dbaggott/claude-plugins
```

Then, as a separate command — the install can't run until the marketplace add
completes, and pasting both at once only registers the first as a slash command:

```
/plugin install dnbg-workflow@dnbg --scope user
```

> Three names, deliberately different. The **repo** is `claude-plugins` (it
> can host more than one plugin), the **plugin** is `dnbg-workflow`, and the
> **marketplace** is `dnbg` — hence `dnbg-workflow@dnbg`. Claude Code rejects
> marketplace names containing "claude" as impersonating an Anthropic-official
> marketplace, which is why the marketplace needed a name of its own.

At `--scope user` the plugin is active in every session on the machine, in any
directory. That is the intended setup: a per-repo install means the rules fire
in some directories and not others depending on where Claude Code was launched
from, which is the worst of both worlds.

## Configure which repos it enforces on

**This step is what turns the hooks on.** At enable time Claude Code prompts for
one value:

| Setting | Meaning |
| --- | --- |
| `owners` | Comma-separated GitHub orgs and/or personal logins — e.g. `acme-corp,yourname` |

A repository is **covered** when its `origin` remote points at one of those
owners. In a covered repo the two hooks below block; everywhere else they do
nothing.

**Leave it empty and nothing is ever blocked.** The skills still load and still
advise, but no hook halts an edit. That is the deliberate default: a plugin that
can stop your work shouldn't start doing so before you've said where.

To change it later, re-run the plugin's configuration from `/plugin`. The value
is stored in your **user** `settings.json`; a project's `.claude/settings.json`
is deliberately ignored for plugin config, so cloning a repo can never
reconfigure this.

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
| `prototype-velocity` | Opt-in: how to size work in a project with no users yet |

The `reviewer` pair is the piece with the least in common with the rest — it
exists because GitHub won't let you approve your own PR, and a separate App
identity can. `reviewer-setup` creates that App and keeps its private key on
your machine.

`prototype-velocity` is **opt-in per repo** and off unless a project asks for
it, since it trades away protections real users need. A repo opts in with one
line in its own `CLAUDE.md`:

> This project is prototype-stage — load `dnbg-workflow:prototype-velocity` when
> sizing a change or deciding whether to split a PR.

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
dnbg-workflow/                    # the plugin
  .claude-plugin/plugin.json      # manifest, incl. the `owners` userConfig
  always-on-rules.md              # injected into every session
  hooks/                          # auto-update, rule injection, two gates
  skills/                         # loaded on demand when the description matches
```

Changes go through a PR — never push to `main` directly.

### Versioning

Calendar versioning (`YYYY.N`), where `N` is the Nth release of the year and
resets each January. `.github/workflows/auto-bump-version.yml` bumps it after
every merge to `main`, so authors never touch the version in a PR. Run
`claude plugin list` to see what you have installed.

Semver would be fictional here: the plugin ships rules and skills, not an API,
so there is no breaking change to anchor a major bump on. CalVer answers the
only question a consumer actually has — how fresh is this?

### If you forked this

Nothing in the plugin itself assumes this repo's setup — which repos it enforces
on is the `owners` config, and the skills read a repo's merge settings rather
than assuming them. The **CI** is a different matter, since a fork inherits
`.github/workflows/` verbatim:

- **`ci.yml`** works anywhere. It runs shellcheck and validates the JSON. Whether
  its `ci-required` umbrella actually *blocks* merges is your branch-protection
  setting, not something this repo can decide for you.
- **`auto-bump-version.yml`** needs a GitHub App, because a required status check
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
