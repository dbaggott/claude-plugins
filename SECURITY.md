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
each time** — that is what a Claude Code hook is. Four hooks fire automatically
once the marketplace is trusted:

| Hook | Fires | What it does |
| --- | --- | --- |
| `inject-rules.sh` | session start | Prints `always-on-rules.md` to stdout, which Claude Code puts in the session's context. |
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
`issue-workflow` skill was loaded this session
(`check-issue-create.sh:98-100`). What it learns is one yes/no. The transcript
is not parsed further, and nothing from it is kept, written, or sent.

**The hooks make no network calls, write no files, and hold no credentials.**
They shell out to `jq`, `git`, `grep`, `sed` and `tr`. Nothing in this project
updates itself — what you installed is what runs until you update
deliberately, so reviewing
[`dnbg-workflow/hooks/`](dnbg-workflow/hooks/) once is a review that stays
valid. They are short, and reading code that will run in your terminal before
you trust it is a reasonable thing to want.

**The skills are different, and the difference is consent.** A skill is text
that Claude loads on demand; the commands it describes — `gh`, `git`, `curl`,
`openssl`, `python3` — run when you ask for that workflow, under your own
credentials, in the session you are watching. The `reviewer` skill is the one
exception worth reading closely, because it is the only component that holds a
long-lived secret; it has its own section below.

The watcher scripts (`watch-pr.sh`, `watch-merge.sh`) write a trace log per run
to `${TMPDIR:-/tmp}/dnbg-watch/`, swept after three days. It records the
repo, PR number and poll outcomes so a watch that dies can be diagnosed — no
tokens, no diff content. `WATCH_LOG=off` disables it.

### What it does not do

No telemetry. No analytics. Nothing sends your code, prompts, or session
contents anywhere. No server component, no hosted service, no shared secret,
no webhook — the reviewer App is created without one deliberately
(`bootstrap.py:64-66`), so GitHub never calls out to anything. No credential
is read from a repository you clone: the reviewer's key sources are your user
config and environment only, never the working directory.

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

## The reviewer bot's private key

`reviewer-setup` creates a GitHub App under your account and saves its private
key on your machine. That key is the bot's entire credential: anyone holding it
can mint installation tokens for every account the App is installed on, without
your GitHub session and without touching your account.

**What it can do.** The App is created least-privilege
(`bootstrap.py:77-84`): `pull_requests: write` — submit reviews, inline
comments, thread replies — plus `contents`, `checks`, `actions`, `statuses` and
`metadata` at **read**. Deliberately absent: `contents: write` (a reviewer
should not be able to write source) and `issues` (the issue-scoped review mode
runs under your own auth instead). So a leaked key reads private source on
every repo where the App is installed, and writes reviews and comments as the
bot — it cannot push code, merge, or alter issues.

**Where it lives.** Three sources, first hit wins: the
`DNBG_REVIEWER_PRIVATE_KEY` environment variable, a command you configure via
`DNBG_REVIEWER_PRIVATE_KEY_COMMAND` or `private_key_command` in `config.json`
(any secret manager), or a plaintext PEM at
`~/.config/dnbg/reviewer/private-key.pem`, mode `0600` in a `0700` directory —
the default `bootstrap.py` writes. The
[README](README.md#the-reviewer-bots-private-key) covers configuring these and
why the plaintext default is a considered choice rather than an oversight.

The key never leaves your machine: `mint-token.sh` signs a ~9-minute JWT
locally and exchanges it for a short-lived installation token, and only that
token is ever sent.

### If the key is exposed

Assume exposure if the PEM was committed, pasted, backed up somewhere
unencrypted, or sat on a machine you no longer control. Deleting a file or
force-pushing over a commit does **not** revoke anything — the key stays valid
until GitHub is told otherwise.

Do these in order, in your App's settings on GitHub
(`https://github.com/settings/apps/<slug>`; your slug is in
`~/.config/dnbg/reviewer/config.json`):

1. **Generate a replacement key, then delete the exposed one.** That order is
   forced: an App must always have at least one key, so the old one cannot be
   deleted until a new one exists. Deleting it invalidates it immediately.
   Only key *deletion* revokes — rotating the file on your disk does nothing.
2. **Install the replacement.** Put the downloaded PEM wherever your setup
   resolves the key from (by default `~/.config/dnbg/reviewer/private-key.pem`,
   mode `0600`), then confirm with `mint-token.sh <owner>`.
3. **Consider the tokens already minted.** An installation token
   [expires after 1 hour](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app),
   so anything minted before you rotated is good for up to that long. GitHub
   does not document whether deleting the key invalidates tokens already
   issued from it — assume it does not. If that hour matters, uninstall the
   App from the affected accounts, which removes the installation those tokens
   are scoped to, and reinstall afterwards.

If you would rather retire the App than rotate it, deleting it revokes
everything in one step; re-run `bootstrap.py` to create a fresh one. Note that
`bootstrap.py` cannot repair an existing App — GitHub returns an App's key
exactly once, at creation (`bootstrap.py:12-15`), so re-running it always
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
