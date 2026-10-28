# Security policy

## Reporting a vulnerability

**Report privately through GitHub:
[open a draft advisory](https://github.com/dbaggott/claude-plugins/security/advisories/new)**
(repo → **Security** → **Report a vulnerability**). A report there is visible
only to you and the maintainer — no email address is published, and no
third-party service is involved.

Please don't open a public issue for anything you believe is exploitable — the
whole point of the private channel is that a fix can land before the details
are public.

Useful in a report: which plugin and version, what an attacker controls, and
the smallest thing that demonstrates the problem. This is a one-maintainer
project with no on-call rotation, so there is no response-time commitment worth
making; you will get an acknowledgement and, if the report holds, an advisory
crediting you unless you'd rather not be named.

## Supported versions

**The latest release of each plugin, and nothing else.** Plugins version
independently on CalVer (`YYYY.M.N`) and every release is tagged
`{plugin}--v{version}`, so older versions remain *addressable* — but a fix
lands on `main` and ships in the next release of the affected plugin only.
Nothing is backported. If you have pinned an old version, updating is the fix.

`claude plugin list` shows what you have installed.

## What installing this grants

**Hooks ship with `dnbg-workflow` only** — and so with `dnbg-all`, which depends
on it. `dnbg-practices` and `dnbg-work-summary` install skills and nothing else;
neither runs any shell, which is why the first of them describes itself as "No
hooks, no forge."

Installing `dnbg-workflow` means **it runs shell on your machine without asking
each time** — that is what a Claude Code hook is. Five hooks fire automatically
once the marketplace is trusted:

| Hook | Fires | What it does |
| --- | --- | --- |
| `inject-rules.sh` | session start | Prints `always-on-rules.md` to stdout, which Claude Code puts in the session's context. |
| `role-fallback-notice.sh` | session start | Runs `as-role.sh --fallbacks`, which reads each role's local configuration (its `config.json` and whether its `DNBG_<ROLE>_*` variables are set) without using a credential, names any role that would post as your own account because it has no App, and warns when two roles share one App. |
| `inject-rules-subagent.sh` | subagent start | The same text, into each subagent's context. |
| `check-worktree.sh` | before every `Edit`/`Write`/`NotebookEdit` | Reads the target path and the repo's `origin`; **blocks** edits to tracked files in the main checkout of a covered repo. |
| `check-issue-create.sh` | before every `Bash` | Reads the command string; **blocks** `gh issue create` against a covered repo unless the `issue-workflow` skill is loaded. |

The two `PreToolUse` hooks see the tool payload for **every** call of those
types, including in repos this project has nothing to do with.
`check-worktree.sh` takes a file path out of it; `check-issue-create.sh` takes
the command string. Neither logs, stores, or forwards what it sees.

**`check-issue-create.sh` also reads your session transcript**, which is the
most sensitive thing either hook touches and so the one most worth stating
outright. It happens only *after* a command has already matched `gh issue
create` against a covered repo: the hook takes `transcript_path` from the
payload and greps that file for a single pattern, to find out whether the
`issue-workflow` skill was loaded this session. When a subagent runs the command,
the hook reads that subagent's own transcript instead, which it locates from
the payload's `agent_id` (still a single `grep -qE` for the
skill's name, and nothing else reads the file). What it learns is one yes/no. The transcript
is not parsed further, and nothing from it is kept, written, or sent.

**The hooks make no network calls, write no files, and hold no credentials.**
Every binary they invoke is local text-processing or `git` — `jq`, `grep`,
`sed`, `tr` and `awk` among them — and none of it reaches the network.
Nothing in this project updates itself — what you installed is what runs until
you update deliberately, so reviewing
[`dnbg-workflow/hooks/`](dnbg-workflow/hooks/), with the
[`as-role.sh`](dnbg-workflow/scripts/as-role.sh) and
[`lib-role.sh`](dnbg-workflow/scripts/lib-role.sh) that
`role-fallback-notice.sh` runs, once is a review that stays valid. They are short, and reading code that will run in your terminal before
you trust it is a reasonable thing to want.

**The skills are different, and the difference is consent.** A skill is text
that Claude loads on demand; the commands it describes — `gh`, `git`, `curl`,
`openssl`, `python3` — run when you ask for that workflow, under your own
credentials, in the session you are watching. The agent roles' GitHub Apps are
the one exception worth reading closely, because each holds a long-lived
secret; they have their own section below.

The watcher scripts (`watch-pr.sh`, `watch-issue.sh`) write a trace log per run
to `${TMPDIR:-/tmp}/dnbg-watch/`, swept after three days. It records the
repo, PR number and poll outcomes so a watch that dies can be diagnosed — no
tokens, no diff content. `WATCH_LOG=off` disables it.

`git-workflow` writes git config in each worktree it creates: it sets
`extensions.worktreeConfig` in the repository's shared config, and, in that
worktree's own config, a credential helper that pushes as the author role and
an HTTPS push URL for an SSH `origin`. The main checkout's credential helpers
and remotes are left as they were. "The author" below covers what the helper
does.

### What it does not do

No telemetry. No analytics. Nothing sends your code, prompts, or session
contents anywhere. No server component, no hosted service, no shared secret,
no webhook — every role's App is created without one deliberately
(`build_manifest` sets no `hook_attributes`), so GitHub never calls out to
anything. No credential
is read from a repository you clone: a role's key sources are your user config
and environment only, never the working directory.

### The enforcement hooks are not a security boundary

`check-worktree.sh` and `check-issue-create.sh` block things, so it is easy to
read them as a control. They are not, and treating them as one is the mistake
this section exists to prevent:

- **They fail open.** Without `jq` (both) or `git` (`check-worktree.sh`) they
  cannot parse or resolve, and the action proceeds either way — by two different
  routes. A missing `jq` kills the hook under `set -e`, and Claude Code classes a
  hook exiting non-zero and non-2 as a non-blocking error. A missing `git` is an
  explicit allow: `check-worktree.sh:32` exits **0**. `inject-rules.sh` warns at
  session start for exactly this reason, but the gate is inert either way.
- **They gate an agent, not an attacker.** They stop a well-behaved session
  from editing the wrong checkout. Anything that can run `Bash` can also run
  `git`, and nothing here tries to prevent that.

They are workflow guardrails against accidental edits. Please do report a way
to make one misfire *against a repo it should not touch* — that is a real bug —
but a way to deliberately work around your own gate is working as designed.

## Role Apps' private keys

Each agent role that acts on GitHub under its own identity has a GitHub App,
created under your account by `reviewer-setup`, with its private key saved on
your machine. A role's key is that bot's entire credential: anyone holding it can
mint installation tokens for every account the App is installed on, without
your GitHub session and without touching your account. The roles are the
directories under `dnbg-workflow/roles/`; each one's `permissions.json` is the
exact set its App is created with and every mint is checked against.

**How a role acts.** Every write a role makes runs through
`dnbg-workflow/scripts/as-role.sh <role> <repo> -- <command>`, which mints a
short-lived installation token for the App's installation on that repo's owner
and execs the command with it in `GH_TOKEN`. The token exists only in that
process's environment: it is not written to disk, to git config or to a remote
URL, and is not printed. A role with no App acts as your own account only if its
`permissions.json` sets `"fallback": "operator"`, and a notice at session start
names every role doing so. A role whose App is configured but whose credential
fails is an error, never a silent switch to your account.

These Apps are not a boundary between roles. Every role's key sits under the
same OS user, so any agent session can mint any role's token; what separate Apps
buy is honest attribution and a narrower permission set per call.

### The reviewer

`dnbg-workflow/roles/reviewer/permissions.json`: `pull_requests: write` —
submit reviews, inline comments, thread replies — `issues: write`, to post an
issue-body review's verdicts, `contents: write`, and `checks`, `actions`,
`statuses` and `metadata` at **read**. The reviewer never falls back. With no
author App, the author's watch ignores exactly your login, so a review posted as
you would never wake it, and GitHub refuses your approval of a PR you opened.
With one, a review under your login would read as your own.

⚠️ **`contents: write` means a leaked key can write source.** GitHub gates
creating commits and refs on it, and merging a pull request too, so the blast
radius is not read-only: on every repo where the App is installed, a leaked key
reads private source, pushes commits, can merge, writes reviews and comments,
and edits issues as the bot. It is granted because GitHub also gates two things
the reviewer cannot work without on it — resolving a review thread, and having
its verdict counted at all — and offers no narrower permission for either.

The scoping lever is therefore the installation's repository list, not the
permission set. An App you have granted more to for other purposes can do
whatever you granted.

### The orchestrator

`dnbg-workflow/roles/orchestrator/permissions.json`: `issues: write`, to post
decision-log rows and questions, edit tracking-issue bodies and claim issues for
its authors, and the mandatory `metadata: read`. On every repo where the App is
installed, a leaked key reads and writes any issue's body, comments and labels
as the bot, and nothing more: with no `contents` or `pull_requests` permission,
it cannot push, merge, or read the repository's code or its pull requests' diffs. Without an App the orchestrator falls back to
your account, and the session-start notice says so. Rotate its key as below,
with `orchestrator` as the role.

### The author

`dnbg-workflow/roles/author/permissions.json`: `contents: write`, to push
branches; `pull_requests: write`, to open, edit and mark ready PRs and answer
review threads; `issues: write`, to claim, file, edit and comment on issues;
`workflows: write`, without which GitHub refuses a push that touches
`.github/workflows/`; and `checks`, `actions`, `statuses` and `metadata` at
**read**. It has no administration permission. Commits stay yours: the author
App pushes them and opens the PR, and changes no author or committer.

⚠️ **A leaked author key pushes code, workflow files included, to every repo
where the App is installed.** A pushed workflow runs in CI with whatever secrets
the repo gives it, so on a repo with secrets the key reaches those too. It can
also merge, open and edit PRs, and edit issues as the bot. As for the reviewer,
the scoping lever is the installation's repository list.

The author falls back to your account when it has no App, and that is a
supported configuration rather than a migration step: its writes and pushes go
up as you, as they did before roles existed.

**Pushes.** `git-workflow` configures each worktree it creates, in that
worktree's own git config, with `dnbg-workflow/scripts/git-credential-as-role.sh
author` as its only credential helper; the main checkout's config is untouched.
On each `get`, the helper mints through `as-role.sh` and hands the token to git
on the credential protocol, so nothing is stored (`store` and `erase` do
nothing) and the token reaches no config file, remote URL or log. A configured
author whose mint fails stops the push; it is never answered with your
credential. With no author App, the helper hands on your own
`gh auth git-credential` answer. An SSH `origin` gets an HTTPS push URL in the
worktree config, so the helper is asked at all; with no author App, those pushes
use `gh`'s OAuth token instead of your SSH key, and that token needs the
`workflow` scope to push a workflow change (`gh auth status` lists its scopes;
`gh auth refresh -s workflow` adds one).

Rotating or revoking the author's key is the procedure below, for the author's
App.

### Where a key lives

Three sources per role, first hit wins, shown for the reviewer (each role has
its own `DNBG_<ROLE>_*` set and `~/.config/dnbg/<role>/` directory): the
`DNBG_REVIEWER_PRIVATE_KEY` environment variable, a command you configure via
`DNBG_REVIEWER_PRIVATE_KEY_COMMAND` or `private_key_command` in `config.json`
(any secret manager), or a plaintext PEM at
`~/.config/dnbg/reviewer/private-key.pem`, mode `0600` in a `0700` directory —
the default `bootstrap.py` writes.
[`docs/configuration.md`](docs/configuration.md#role-apps-private-keys)
covers configuring these and why the plaintext default is a considered choice
rather than an oversight.

The key never leaves your machine: `mint-token.sh` signs a ~9-minute JWT
locally and exchanges it for a short-lived installation token, and only that
token is ever sent. The JWT reaches `curl` through a pipe rather than on its
command line, which other users on the machine can read.

### If the key is exposed

Assume exposure if the PEM was committed, pasted, backed up somewhere
unencrypted, or sat on a machine you no longer control. Deleting a file or
force-pushing over a commit does **not** revoke anything — the key stays valid
until GitHub is told otherwise.

Do these in order, for the exposed role's App, in its settings on GitHub
(`https://github.com/settings/apps/<slug>`; the slug is in
`~/.config/dnbg/<role>/config.json`):

1. **Generate a replacement key, then delete the exposed one.** That order is
   forced: an App must always have at least one key, so the old one cannot be
   deleted until a new one exists. Deleting it invalidates it immediately.
   Only key *deletion* revokes — rotating the file on your disk does nothing.
2. **Install the replacement.** Put the downloaded PEM wherever your setup
   resolves the key from (by default `~/.config/dnbg/<role>/private-key.pem`,
   mode `0600`), then confirm with `as-role.sh <role> <owner>/<repo> -- true`.
3. **Consider the tokens already minted.** An installation token
   [expires after 1 hour](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app),
   so anything minted before you rotated is good for up to that long. GitHub
   does not document whether deleting the key invalidates tokens already
   issued from it — assume it does not. If that hour matters, uninstall the
   App from the affected accounts, which removes the installation those tokens
   are scoped to, and reinstall afterwards.

If you would rather retire the App than rotate it, deleting it revokes
everything in one step; re-run `bootstrap.py --roles <role>` to create a fresh
one. Note that
`bootstrap.py` cannot repair an existing App — GitHub returns an App's key
exactly once, at creation (`convert_manifest` is the one-shot exchange that
receives it), so re-running it always
produces a *new* App with a new identity. Keeping the same bot means generating
the replacement key in App settings, per step 1.

GitHub's docs carry the current click-path for each of these:
[managing private keys](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps)
and
[deleting a GitHub App](https://docs.github.com/en/apps/maintaining-github-apps/deleting-a-github-app).

**If it was committed**, rotate first — the steps above — and only then worry
about the history. Rewriting history is not a substitute for rotation: the
commit may already be cloned, cached by GitHub, or indexed. If the repo is
public, treat the key as compromised from the moment it was pushed.
