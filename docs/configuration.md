# Configuration

Every value here is optional. Leave all of them alone and the plugin still
works — it loads its skills and rules, advises, blocks nothing, and publishes
nothing you didn't write.

- [Install scope](#install-scope) — which of two adoption modes you're in
- [`owners`](#owners--which-repos-it-enforces-on) — **the only setting that turns the hooks on**
- [`worktree_path`, `claim_label`, `retrospective_dir` and `followup_dir`](#the-mechanical-opinions) — names and paths you can change
- [`version_stamp`](#version_stamp--recording-which-prompts-published-what) — off by default; adds a hidden version marker to what you publish
- [Agent roles](#agent-roles--whose-login-each-agent-posts-under) — each role's App, the resolver, and the fallback to your own account
- [Role Apps' private keys](#role-apps-private-keys) — where each is read from

## Install scope

The install asks for one. Which you want depends on whether you're adopting this
for **yourself across many repos** or for **one repo shared with other people** —
the two are different problems and the plugin supports both.

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

## `owners` — which repos it enforces on

**This is what turns the hooks on, and it only matters in Mode A.** It is the
first of the values Claude Code prompts for at enable time — the others are
below, and none of them turns any *enforcement* on or off:

| Setting | Meaning |
| --- | --- |
| `owners` | Comma-separated GitHub orgs and/or personal logins — e.g. `acme-corp,yourname` |

A repository is **covered** when its `origin` remote points at one of those
owners. In a covered repo the two hooks block; everywhere else they do
nothing. Matching ignores case and whitespace, and compares whole names — so
`acme` does not match `acme-corp`.

**Leave it empty and nothing is ever blocked.** The skills still load and still
advise, but no hook halts an edit. That is the deliberate default: a plugin that
can stop your work shouldn't start doing so before you've said where.

To change it later, re-run the plugin's configuration from `/plugin`. The value
is stored in your **user** `settings.json` — and unlike `enabledPlugins`, plugin
config is deliberately *not* read from a project's `.claude/settings.json`, so a
repository you clone can never widen or narrow what gets enforced on your
machine. That asymmetry is also why the opt-in for `velocity-tradeoff` goes
through a repo's `CLAUDE.md` rather than through config.

## The mechanical opinions

Some of this plugin's choices are mechanical — where worktrees go, what a claim
is labelled, and where retrospectives and follow-up entries are kept — and you
can change them without forking. Each defaults to what the skills say, so leaving
them alone is the same as not having them:

| Setting | Default | Meaning |
| --- | --- | --- |
| `worktree_path` | `.worktrees` | Repo-relative directory worktrees are created in. Must stay inside the repo and must be a plain path — an absolute path, a `~` path, any `..` segment, a leading `-`, or a character outside letters, digits and `. _ - /` is rejected and the default used instead |
| `claim_label` | `assigned:agent-session` | Label an agent session applies when it claims an issue. Must start with `assigned:` |
| `retrospective_dir` | `~/.claude/dnbg-retrospectives` | Where `orchestrate`'s agents write their retrospectives, one subdirectory per repo (`<dir>/<owner>/<repo>/`), and where `process-review` reads them. Must be an absolute path or one under `~/`, with the same character rule as `worktree_path`; anything else is rejected and the default used instead |
| `followup_dir` | `~/.claude/dnbg-followups` | Where agents write a follow-up entry for each Actionable item in their reports, one subdirectory per repo (`<dir>/<owner>/<repo>/`), and where `followup-review` reads them. Same rule as `retrospective_dir` |

Set one and the session-start hook prints a short note saying so; the skills read
that note as overriding the defaults they spell out. Set nothing and the hook
prints nothing at all.

**These are user-scope too**, for the same reason `owners` is: plugin config is
read from your **user** `settings.json` and deliberately not from a project's
`.claude/settings.json`. So in Mode B a repository cannot set a worktree
directory for everyone who clones it — each collaborator sets their own, or
leaves the default. That is the same asymmetry that stops a cloned repo widening
what gets enforced on your machine, and it costs the same thing here.

**The rejections are enforced rather than advisory, and for the same kind of
reason.** Worktrees outside the repo are not covered by `.gitignore` and the
skills' cleanup steps stop resolving against them; a path carrying a space, a
leading dash, or a shell metacharacter renders a `git worktree add` that cannot
run as printed, and the printed command is the whole point of the block message.
A claim label outside `assigned:` is worse, because it fails silently in *both*
directions: the check
for an existing claim matches the whole `assigned:` namespace deliberately, so
that any claimant — another agent, a bot, a teammate's tooling — is visible
without this plugin knowing their name. Step outside it and your claims stop
being seen by them while theirs stop being seen by you, which puts two workers on
one issue. A retrospective or follow-up directory is the reverse of a worktree
root, outside every repo by design, so it has to name a place on its own: a
relative path would land in whichever checkout the writing agent happened to
stand in. Its
character rule is the worktree one, because an agent retypes the value into the
command that creates it. Where a value is rejected, the session-start note
names the value, the reason, and the default it fell back to.

What is deliberately **not** configurable: PRs always open as drafts, the
send-to-review picker and its fixed option order, the `[<branch-name>]` sibling
PR title tag, and "only a human merges". Those are what the workflow *does*
rather than parameters of it — the tag in particular is a join key, so a
per-adopter format would destroy the signal exactly when someone is reading a PR
list across repos.

## `version_stamp` — recording which prompts published what

| Setting | Default | Meaning |
| --- | --- | --- |
| `version_stamp` | off | Append `<!-- dnbg-workflow <version> -->` to PR descriptions, review bodies, and issue claim comments |

Turn it on and three surfaces carry an HTML comment naming the plugin and the
version that produced them: the PR description `git-workflow` writes, the review
body `reviewer` posts, and the claim comment `issue-workflow` leaves on an issue.
It renders invisibly, so nobody reading the PR sees it, and
`gh pr view <n> --json body` is enough to read it back out.

**It answers a question nothing else can.** A transcript records the plugin's
*name* and Claude Code's version, never the plugin's own, and transcripts expire
on a rolling window while a merged PR does not. So without the stamp, "which
version of these prompts wrote this review" has no answer six months later —
which matters exactly when you have changed a skill and want to know whether the
PRs that went sideways predate the fix.

**It is off by default because the stamp lands on other people's screens.** Every
other value here changes how the plugin behaves on your machine; this one adds
text to artifacts published under your name, in repos you may share with people
who never installed this plugin and did not agree to carry a marker for it.
Something with that reach should be something you switched on, and a default of
off costs only the provenance you didn't ask for. The same reasoning sets the
failure direction: a value the hook can't make sense of leaves the stamp **off**
rather than on, and with it off the session-start note carrying the version is
not emitted at all — so a skill has no version to stamp with rather than a
decision to make. None of them will substitute one from the manifest or from
memory, since a guessed version reads downstream exactly like a genuine one.

Two things it is not. It is **not** a per-repo setting — like every value here it
is read from your **user** `settings.json`, so it is on for all your repos or
none. And it does **not** stamp commits, issue bodies, or inline review comments;
only the three surfaces above, each of which is a single artifact whose author is
already you.

## Opting a repo into `velocity-tradeoff`

`velocity-tradeoff` is **opt-in per repo** and off unless a project asks for
it, since it trades away protections most projects need. Whether the trade holds
is a ratio — blast radius, reversibility, how fast breakage is noticed, test
coverage, and users — not a headcount, so a live project with forgiving users and
one-command rollback can sit on the velocity side while a pre-launch one doing an
irreversible migration cannot.

A repo opts in with a short section in its own `CLAUDE.md` naming the posture and
who can unmake it; the skill carries the template. It goes through `CLAUDE.md`
rather than plugin config for the same reason `owners` is user-scope: a cloned
repository must not be able to change what your machine enforces, and this is
the one direction where the repo genuinely is the right authority — it is the
project, not the machine, that has the risk profile.

## Agent roles — whose login each agent posts under

The agents act on GitHub in roles, and a role with a GitHub App of its own posts
under that App's bot login rather than yours. Each role is a directory under
`dnbg-workflow/roles/<role>/` holding its `permissions.json`: the permissions its
App is created with and every minted token is checked against, and its
`fallback`. The `reviewer-setup` skill creates the Apps, for any subset of
roles, in one run.

| Per role | Default | Override |
| --- | --- | --- |
| Config directory | `~/.config/dnbg/<role>/` | `DNBG_<ROLE>_CONFIG_DIR` |
| App id, installation, key | `config.json`, `private-key.pem` there | `DNBG_<ROLE>_APP_ID`, `_INSTALLATION_ID`, `_PRIVATE_KEY`, `_PRIVATE_KEY_COMMAND` |
| Login (App slug) | `slug` in `config.json` | `DNBG_<ROLE>_SLUG` |

`<ROLE>` is the role's name upper-cased, with hyphens as underscores
(`DNBG_REVIEWER_*`). The reviewer's existing directory and variables are this
layout, so a setup made before roles existed keeps working.

### The resolver

`dnbg-workflow/scripts/as-role.sh` is the one place that knows how a role
reaches the forge; skills and scripts ask it. `<repo>` is `owner/name` (short
for `github.com/owner/name`), `host/namespace/name`, or a remote URL — never a
bare owner. Only github.com is implemented.

| Call | Answer |
| --- | --- |
| `as-role.sh <role> <repo> -- <cmd…>` | Runs `<cmd…>` with the role's token in `GH_TOKEN`, after one stderr line `as-role.sh: result=OK as=<login> fallback=<none\|unconfigured>`. If the resolver fails, the command does not run: exit 125, with `as-role.sh: result=ERROR reason=<reason>` on stderr. |
| `as-role.sh --login <role> <repo>` | `result=OK login=<login> fallback=<none\|unconfigured>` — the App slug (GitHub's REST spelling adds `[bot]`), or your login when the role falls back. |
| `as-role.sh --operator <repo>` | `result=OK login=<your login> fallback=none`, read under your own `gh` auth with no role token in place. |
| `as-role.sh --fallbacks` | `result=OK roles=<role,…\|none>`: the roles that would act as you, read from configuration presence only, with no network call. The session-start notice uses it. |

The last three print exactly one line on stdout and exit 0; when they cannot
answer, that line is `result=ERROR reason=<reason>`, with what to do on stderr.
A configured role whose login is unknown (an env-only setup without
`DNBG_<ROLE>_SLUG`) answers `--login` with `reason=no-login`, never with your
login. Since a wrapped command can exit 125 itself, the credential form's stderr
`result=ERROR` line, not the exit status, is what says the resolver refused.

The token is minted for the App's installation on the repo's owner, lives only
in the command's environment, and is never written to disk, git config or a
remote URL, or printed.

### Falling back to your account

A role with no configuration (no `config.json`, and none of
`DNBG_<ROLE>_APP_ID`, `_PRIVATE_KEY` or `_PRIVATE_KEY_COMMAND`) acts as your own
account only when its `permissions.json` says
`"fallback": "operator"`; the reviewer says `"refuse"`, which is also what an
absent key means. A session-start notice names each role falling back, from
configuration presence alone, with no network call. A role that *is* configured
but whose credential fails — a failed mint, a revoked grant, a key command that
prints nothing — is an error and never falls back, and so is any setup where two
roles resolve to the same App.

## Role Apps' private keys

That key is the bot's entire credential, so it's worth being explicit about how
it's handled rather than leaving you to read the scripts. [`SECURITY.md`](../SECURITY.md)
covers what a leaked key can do and how to revoke one; this section covers where
the key is read from. It is shown for the reviewer; every role reads the same
three sources from its own `DNBG_<ROLE>_*` variables and directory.

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

- **The command runs on every mint**, and a role mints per write.
  If yours prompts — a Touch ID or vault unlock on `op read` — you will see that
  prompt repeatedly during a busy PR. Nothing here caches the key.
- **Route 1 puts the PEM in your environment**, where any process you own can
  read it (`/proc/PID/environ` on Linux). Exporting it from a shell profile is
  arguably worse than the `0600` file it replaces. It is meant for CI, where the
  runner is ephemeral and the secret store injects it for one job.

Three properties worth knowing:

- **The command is read only from your user config or environment — never from a
  repository.** Nothing reads config from the working directory. This is the
  property the feature's safety rests on: the command is harmless because anyone
  who can write `~/.config/dnbg/<role>` can already edit your shell profile,
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
