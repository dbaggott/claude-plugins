# claude-plugins

A Claude Code plugin marketplace, published as `dnbg`. It hosts four plugins: a
GitHub workflow, a GitHub work recap, coding practices that work anywhere, and a
bundle of all three. Which forges are supported, and what happens on one that
isn't, is [below](#supported-forges).

## `dnbg-workflow`

An opinionated GitHub workflow: every change goes through a worktree and a draft
PR, issues are written to survive a cold handoff, and an independent bot identity
reviews the result.

It is a set of **skills** (loaded on demand when they match the task), a short
**always-on rules** file, and two **enforcement hooks** that make the worktree
and issue flows non-optional in the repos you choose.

### Supported forges

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

So support is stated per forge. **Status** describes the forge-coupled skills —
the forge-neutral ones already work everywhere, which is what the third column
says:

| Forge | Forge-coupled skills | Forge-neutral skills | Status |
| --- | --- | --- | --- |
| GitHub | yes | yes | **Supported** |
| GitLab | no | yes | [Planned](https://github.com/dbaggott/claude-plugins/issues/21) |
| Bitbucket | no | yes | [Planned](https://github.com/dbaggott/claude-plugins/issues/21) |
| Azure Repos | no | yes | Not planned |
| Anything else, including self-hosted and GitHub Enterprise | no | yes | Unsupported |

Which skills are which is the **Forge** column of [What's in
it](#whats-in-it) — and read the **Plugin** column beside it, because
*forge-neutral is a property of the skill, not of the plugin shipping it*. The
two neutral skills are obtained differently: `coding-practices` ships in
`dnbg-practices`, which mentions no forge anywhere and installs on its own
(`/plugin install dnbg-practices@dnbg`), while `velocity-tradeoff` ships inside
`dnbg-workflow` because it governs how to size a change and whether to split a
PR — a workflow question. A non-GitHub user therefore gets `velocity-tradeoff`
only by installing the GitHub-coupled plugin, where it then works normally: the
"yes" in the third column above is a per-skill promise, and a `dnbg-workflow`
install on GitLab keeps it.

### What happens on an unsupported forge

**It declines; it does not adapt.** A forge-coupled skill says plainly that the
flow is GitHub-only, names the host it actually found, and hands back to
whatever flow your project already uses. It will not run a `gh` command that
cannot succeed, and it will not translate itself to `glab` or the Bitbucket API
— a half-translated flow is worse than either extreme, and translating properly
is [the multi-forge
roadmap's](https://github.com/dbaggott/claude-plugins/issues/21) job rather than
something to do by halves here.

*What* it checks differs by skill, because the five coupled skills don't all act
on the repo you're standing in:

| Skill | Acts on | Declines when |
| --- | --- | --- |
| `git-workflow` | the repo whose tracked file you're changing | that repo's `origin` host isn't `github.com` |
| `issue-workflow` | the repo the issue lives in | the host **in the issue URL** isn't `github.com` — or, for a bare issue number, that repo's `origin` |
| `reviewer` | a pull request you name explicitly | the *named* repo isn't on GitHub |
| `reviewer-setup` | a GitHub App on your machine | never — no repo is involved |
| `work-summary` | your GitHub account, via `gh search` | never — no repo is involved |

The last three deliberately ignore your working directory, and so does
`issue-workflow` whenever the issue is named by full URL — which the always-on
rule requires, so it is the normal case. Asking for a recap of your GitHub week,
or picking up a GitHub issue, while sitting in a GitLab checkout is a coherent
request, and gating it on `git remote get-url origin` would refuse a flow that
works fine. Only `git-workflow` reads that remote unconditionally, because the
file you are editing really is in the repo you are standing in.

Two cases that are *not* a decline, wherever `origin` **is** the input: a repo
with **no `origin`** carries no forge claim either way, so the flow proceeds and
lets you direct rather than assuming either host; and where **several remotes**
exist, `origin` decides — matching what the enforcement hooks do.

The forge-neutral skills are never gated, on any host. That includes
`velocity-tradeoff` despite its plugin: declining is decided per skill, never
per plugin, so a plugin-level gate would be a bug rather than a shortcut.

Only `github.com` remotes are ever covered by the enforcement hooks, so listing
an owner cannot gate a same-named org on another host.

## Requirements

**Claude Code v2.1.207 or newer.** The manifest format has no field for a
minimum version, so this is documented rather than enforced — nothing stops an
older client installing the plugin and misbehaving quietly. It is a floor
derived from the dated behaviors the plugin relies on, not a tested boundary:
plugin config reaches the hooks as `CLAUDE_PLUGIN_OPTION_*` environment
variables, which is the arrangement that settled at v2.1.207 when
`${user_config.*}` stopped substituting into shell-form fields, and `dnbg-all`
resolves its `dependencies`, which arrived at v2.1.143. Verified working on
v2.1.226.

**Command-line tools.** Not all of them are needed for all of it — the first two
are what the enforcement hooks run on, and the last three only matter if you use
the reviewer bot:

| Tool | Needed for | Without it |
| --- | --- | --- |
| `jq` | Both enforcement hooks parse their stdin payload with it | **Enforcement is off.** Ships with macOS 15+; install it on Linux and on older macOS |
| `git` | `check-worktree.sh` resolves the edited path to a repo | **`check-worktree` never fires**; `check-issue-create` still gates a `--repo`-qualified command |
| `gh` | Every workflow skill, for all PR/issue/review operations | The skills cannot run |
| `python3` | `reviewer-setup`'s `bootstrap.py` (stdlib only) | Cannot create the reviewer App |
| `openssl` | `mint-token.sh` signs the App JWT locally | Cannot mint a reviewer token |
| `curl` | `mint-token.sh` exchanges that JWT with GitHub | Cannot mint a reviewer token |

The two hooks **fail open**, so a missing `jq` or `git` does not block your work
— it silently stops protecting it. Claude Code classes a hook exiting non-zero
and non-2 as a non-blocking error: the edit proceeds, you get a `hook error`
notice naming the missing binary, and *Claude does not see that notice at all*,
so the agent goes on believing the gates are live. `inject-rules.sh` therefore
checks at session start and says so once, in output both you and Claude can see.
Making the gates fail closed instead was considered and rejected: a gate learns
which repo an edit targets by parsing its payload, so with no parser it cannot
tell a covered repo from any other, and the only available "closed" is blocking
every edit on the machine.

`mint-token.sh` checks for its own three and exits with a clear message, so
those fail loudly at the point of use rather than needing a session-start
warning.

**Platform: macOS and Linux.** Both are exercised. The hooks are `bash` scripts
using `date`, `mkdir`, `$HOME/.cache`, and `#!/usr/bin/env bash`; they are
expected to work under Git Bash on Windows, but that has never been tested and
is not claimed.

## Install

```
/plugin marketplace add dbaggott/claude-plugins
```

Then, as a separate command — the install can't run until the marketplace add
completes, and pasting both at once only registers the first as a slash command:

```
/plugin install dnbg-all@dnbg
```

`dnbg-all` installs all three. To take only part of it, install what you want
instead — they are independent, and none requires another:

| Plugin | What you get |
| --- | --- |
| `dnbg-workflow@dnbg` | The GitHub workflow, its two enforcement hooks, and the reviewer bot. GitHub, except `velocity-tradeoff` |
| `dnbg-practices@dnbg` | Coding practices. No hooks, no forge, works anywhere |
| `dnbg-work-summary@dnbg` | PR recaps. No hooks. GitHub |

> Three names, deliberately different. The **repo** is `claude-plugins`, a
> **plugin** is e.g. `dnbg-workflow`, and the **marketplace** is `dnbg` — hence
> `dnbg-workflow@dnbg`. Claude Code rejects
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

**This is what turns the hooks on, and it only matters in Mode A.** It is the
first of the three values Claude Code prompts for at enable time — the other two
are below, and neither of them turns anything on or off:

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
machine. That asymmetry is also why the opt-in for `velocity-tradeoff` below
goes through a repo's `CLAUDE.md` rather than through config.

## Configure the mechanical opinions

Two of this plugin's choices are mechanical — a directory name and a label name —
and you can change them without forking. Both default to what the skills say, so
leaving them alone is the same as not having them:

| Setting | Default | Meaning |
| --- | --- | --- |
| `worktree_path` | `.worktrees` | Repo-relative directory worktrees are created in. Must stay inside the repo and must be a plain path — an absolute path, a `~` path, any `..` segment, a leading `-`, or a character outside letters, digits and `. _ - /` is rejected and the default used instead |
| `claim_label` | `assigned:agent-session` | Label an agent session applies when it claims an issue. Must start with `assigned:` |

Set one and the session-start hook prints a short note saying so; the skills read
that note as overriding the defaults they spell out. Set nothing and the hook
prints nothing at all.

**These are user-scope too**, for the same reason `owners` is: plugin config is
read from your **user** `settings.json` and deliberately not from a project's
`.claude/settings.json`. So in Mode B a repository cannot set a worktree
directory for everyone who clones it — each collaborator sets their own, or
leaves the default. That is the same asymmetry that stops a cloned repo widening
what gets enforced on your machine, and it costs the same thing here.

**Both rejections are enforced rather than advisory, and for the same kind of
reason.** Worktrees outside the repo are not covered by `.gitignore` and the
skills' cleanup steps stop resolving against them; a path carrying a space, a
leading dash, or a shell metacharacter renders a `git worktree add` that cannot
run as printed, and the printed command is the whole point of the block message.
A claim label outside
`assigned:` is worse, because it fails silently in *both* directions: the check
for an existing claim matches the whole `assigned:` namespace deliberately, so
that any claimant — another agent, a bot, a teammate's tooling — is visible
without this plugin knowing their name. Step outside it and your claims stop
being seen by them while theirs stop being seen by you, which puts two workers on
one issue. Where a value is rejected, the session-start note names the value, the
reason, and the default it fell back to.

What is deliberately **not** configurable: PRs always open as drafts, the
send-to-review picker and its fixed option order, the `[<branch-name>]` sibling
PR title tag, and "only a human merges". Those are what the workflow *does*
rather than parameters of it — the tag in particular is a join key, so a
per-adopter format would destroy the signal exactly when someone is reading a PR
list across repos.

## What it does to your session

Installing this plugin means **it runs shell scripts on your machine** — plugin
hooks execute automatically once a marketplace is trusted. Specifically:

| Hook | When | What it does |
| --- | --- | --- |
| `inject-rules.sh` | session start | Prints `always-on-rules.md` into the session's context. |
| `inject-rules-subagent.sh` | subagent start | Prints the same rules into each subagent's context. |
| `check-worktree.sh` | before every Edit/Write | **Blocks** edits to tracked files in the main checkout of a covered repo. |
| `check-issue-create.sh` | before every Bash | **Blocks** `gh issue create` against a covered repo unless the `issue-workflow` skill is loaded. |

The rules are injected twice because **`SessionStart` output reaches the main
loop and nothing else** — a subagent spawned from that session receives none of
it. Measured on Claude Code 2.1.226, for the `general-purpose` and `Explore`
agent types. That is why the two hooks exist rather than one, and why they share
`rules-payload.sh`: a subagent working to a different set of rules than its
parent is the failure the split prevents. The rules cost tokens on each subagent
spawn as well as at session start, which is the price of a subagent that has
actually been told to work in a worktree.

Nothing here sends your code anywhere, and **nothing here updates itself**.
These hooks make no network access at all: what you install is what runs until
you update it deliberately. (The skills do drive `gh` — but only when you ask
them to, which is the difference this section is about.) Read the shell
scripts in
[`dnbg-workflow/hooks/`](dnbg-workflow/hooks/) before you trust them — they are
short, and reviewing code that will run in your own terminal is a reasonable
thing to want. Reviewing them is also *durable*, which it would not be if the
plugin replaced them on a timer.

## What's in it

| Skill | Plugin | Forge | For |
| --- | --- | --- | --- |
| `git-workflow` | `dnbg-workflow` | GitHub only | Worktree → draft PR → review → merge → cleanup, end to end |
| `issue-workflow` | `dnbg-workflow` | GitHub only | Writing issues that survive a cold handoff; claiming and resolving one |
| `reviewer` | `dnbg-workflow` | GitHub only | Reviewing a pushed PR under an independent GitHub App identity |
| `reviewer-setup` | `dnbg-workflow` | GitHub only | One-time creation of that App (no cloud service, no shared secret) |
| `velocity-tradeoff` | `dnbg-workflow` | **Any** | Opt-in: how to size work where the risk/benefit trade favors speed |
| `coding-practices` | `dnbg-practices` | **Any** | Design, security, naming, logging, and the smells to stop on |
| `work-summary` | `dnbg-work-summary` | GitHub only | Turning your merged/open PRs into an audience-shaped recap |

`velocity-tradeoff` is the row to notice: the only **Any** inside the
GitHub-coupled plugin, and the case a plugin-level degradation gate would
silently break. See [What happens on an unsupported
forge](#what-happens-on-an-unsupported-forge).

The `reviewer` pair is the piece with the least in common with the rest — it
exists because GitHub won't let you approve your own PR, and a separate App
identity can. `reviewer-setup` creates that App and keeps its private key on
your machine.

### The reviewer bot's private key

That key is the bot's entire credential, so it's worth being explicit about how
it's handled rather than leaving you to read the scripts.

**By default it is a plaintext PEM at `~/.config/dnbg/reviewer/private-key.pem`,
mode `0600`, in a `0700` directory.** That is a deliberate choice, not an
oversight — `aws`, `npm`, and `docker` all keep plaintext credentials in your
home directory, and anyone who can read that file can already read your shell
profile. It is stated here so you can disagree with it, because you have two
ways to.

The key is resolved from the first of these that yields one:

| Order | Source | For |
| --- | --- | --- |
| 1 | `DNBG_REVIEWER_PRIVATE_KEY` | CI and headless runs |
| 2 | `DNBG_REVIEWER_PRIVATE_KEY_COMMAND`, or `private_key_command` in `config.json` | any secret manager |
| 3 | `$CONFIG_DIR/private-key.pem` | the default |

Route 2 is one hook that reaches every manager without this project integrating
with any of them — `op read`, `pass show`, `security find-generic-password -w`,
`secret-tool lookup`, `vault kv get`, `sops -d`. `git`'s `credential.helper` is
the same idea.

Route 1 stands alone: with `DNBG_REVIEWER_APP_ID` set too, no config file or PEM
needs to exist anywhere, which is what makes running the reviewer in CI possible.
`DNBG_REVIEWER_INSTALLATION_ID` is optional alongside it — set it to skip the
`/app/installations` lookup, or leave it and the installation is resolved from
the owner argument. Both fall back to `config.json` when one exists.

Two things to weigh before switching off the default:

- **The command runs on every mint**, and the reviewer mints per review action.
  If yours prompts — a Touch ID or vault unlock on `op read` — you will see that
  prompt repeatedly during a busy PR. Nothing here caches the key.
- **Route 1 puts the PEM in your environment**, where any process you own can
  read it (`/proc/PID/environ` on Linux). Exporting it from a shell profile is
  arguably worse than the `0600` file it replaces. It is meant for CI, where the
  runner is ephemeral and the secret store injects it for one job.

Three properties worth knowing, each of which has a test:

- **The command is read only from your user config or environment — never from a
  repository.** Nothing reads config from the working directory. This is the
  property the feature's safety rests on: the command is harmless because anyone
  who can write `~/.config/dnbg/reviewer` can already edit your shell profile,
  and that stops being true the moment a repo you cloned can supply the value.
- **A key from routes 1 or 2 is never written to disk.** It reaches `openssl`
  through a pipe, so there is no temp file to leak on a crash or a `SIGKILL` —
  the guarantee holds by construction rather than by cleanup. This is the point
  of those routes: if you keep the key in a vault, the tool must not quietly
  materialise it in `/tmp` on every mint. Route 3 hands `openssl` the path it
  already had, because its key is by definition already on that disk — so the
  default setup gains no new dependency.
- **A group- or world-writable config directory or key file is refused**, the way
  `ssh` refuses an over-permissive private key. A key others can *replace* is as
  dangerous as one they can read.

The key never leaves your machine in any case: the scripts sign a ~9-minute JWT
locally and exchange it for a short-lived installation token, and only that token
is sent anywhere.

`velocity-tradeoff` is **opt-in per repo** and off unless a project asks for
it, since it trades away protections most projects need. Whether the trade holds
is a ratio — blast radius, reversibility, how fast breakage is noticed, test
coverage, and users — not a headcount, so a live project with forgiving users and
one-command rollback can sit on the velocity side while a pre-launch one doing an
irreversible migration cannot.

A repo opts in with a short section in its own `CLAUDE.md` naming the posture and
who can unmake it. The skill carries the template.

## Keeping up to date

**This plugin does not update itself.** Once installed it stays exactly as it is
until you update it — which is Claude Code's own default for a third-party
marketplace, and a deliberate one: automatically replacing code that already
runs on your machine is a decision worth making yourself.

An earlier version shipped its own updater and overrode that default. It has
been removed. Claude Code does the same job better, and asking rather than
assuming is the right posture for a plugin that executes on your machine.

**To keep up automatically**, turn on auto-update for this marketplace. Either
set it in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "dnbg": {
      "source": { "source": "github", "repo": "dbaggott/claude-plugins" },
      "autoUpdate": true
    }
  }
}
```

or toggle it in the UI — `/plugin` → **Marketplaces** → **dnbg** → **Enable
auto-update**. The two are the same setting: Claude Code reads the config field
and the panel reflects it.

The path matters. `extraKnownMarketplaces` is also valid in a project's
`.claude/settings.json`, where it prompts *every collaborator* to install the
marketplace — and that file is normally committed. Put this in your user file
unless you mean to ask a whole repo.

Either way, Claude Code checks after each session starts, with a random delay of
up to ten minutes, then refreshes the marketplace and updates installed plugins
on disk. Your running session keeps the version it launched with; you'll be
prompted to `/reload-plugins`, or the new version loads next launch. That is
more current than the removed hook, which throttled itself to once every four
hours.

The config form also works in managed settings, so an administrator can enable
it for an organisation without asking each person to toggle it.

**To update once, by hand**, run these one at a time — submit each, wait, then
the next; pasting them together only registers the first:

```
/plugin marketplace update dnbg
```

```
/reload-plugins
```

The first refreshes the catalog **and** updates the installed plugins from this
marketplace — it reports how many it bumped, and says nothing about plugins when
there was nothing to bump. The second applies them to the running session.

To move a single plugin without refreshing the catalog, use
`/plugin update <plugin>@dnbg`. It reports *already at the latest version* when
there is nothing to do, so silence after a marketplace update usually means the
update already happened rather than that the command failed.

To stop plugin updates globally regardless of the above, set `DISABLE_AUTOUPDATER`.
To keep plugin updates while disabling Claude Code's own, set
`FORCE_AUTOUPDATE_PLUGINS=1` alongside it.

## For maintainers

```
.claude-plugin/marketplace.json   # the catalog
CHANGELOG.md                      # assembled at release time
changelog.d/<plugin>/             # pending fragments, one per PR
dnbg-workflow/                    # the plugin
  .claude-plugin/plugin.json      # manifest, incl. the three userConfig knobs
  always-on-rules.md              # injected into every session
  hooks/                          # rule injection, two gates
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
  universally true, which is why `velocity-tradeoff` is opt-in rather than a
  rule.

If you're tempted to add to `always-on-rules.md`, ask whether a skill
description could fire it instead. If yes, prefer the skill.

## License

[Apache-2.0](LICENSE).
