---
name: reviewer-setup
description: One-time setup creating your own GitHub App for each agent role, so the `reviewer` skill (and any other role defined under `roles/`) posts under an independent bot identity rather than your personal account — GitHub access only, no cloud infrastructure, no shared secret. Load when asked to set up the reviewer bot, create your reviewer App or a role's App, when the `reviewer` skill or `as-role.sh` reports a role is not set up, or to repair or rotate a role's credentials. Each App's private key stays on this machine.
---

# Role App setup

This is the **one-time** bootstrap for the agent roles' identities. For each
role you choose it creates a per-developer **GitHub App**, so that role posts
under a distinct bot identity (e.g. `agent-reviewer-<you>[bot]`) instead of your
personal account. For the reviewer, that separate identity is what makes the
agent an *independent* reviewer and what lets it post a binding `--approve` /
`--request-changes` verdict on any PR — including one you authored, which
GitHub forbids when you review as yourself.

A role is a directory under the plugin's `roles/`, holding the permissions its
App is created with. The roles defined today are whatever
`ls "<skill-dir>/../../roles"` lists. A role with no App behaves as its
`permissions.json` says: the reviewer refuses to run at all, and a role whose
`fallback` is `operator` acts as your own account, which a session-start notice
names.

Everything runs on **GitHub access only**. Each App's private key is generated
during creation, saved on this machine (mode 600), and never leaves it;
`scripts/as-role.sh` signs a short-lived token from it each time the role acts.
No cloud service, no shared secret store.

GitHub Apps are a GitHub construct with no GitLab or Bitbucket equivalent, so
this setup is **GitHub-only** with nothing to degrade to. It is also **not
scoped to any repository** — it creates one App on your machine and installs it
on the accounts you name. Never gate it on the working directory: running it
from a checkout of some other forge's repo, or from no repo at all, is normal
and must work.

## Before you start

- Run from a machine where `gh` is authenticated (`gh auth status`), plus
  `python3`, `openssl`, `jq`, and `curl` available (the setup and review
  helpers need them).
- A role whose credentials already exist (default
  `~/.config/dnbg/<role>/config.json`) is set up; the bootstrap skips it unless
  you name it. Naming it creates a *second* App; only do that deliberately.

## Ownership model

A GitHub App's owner determines where it can be installed, and a **private** App
can only be installed on the account that owns it. To review **both** an org's
repos and your **personal** repos with one bot, it has to be installable on two
different accounts — which forces a **public, user-owned** App. That's the
default, for every role:

- **User-owned, public** (default) — created under your account; public so it can
  be installed on an org *and* on your personal account. Covers org repos +
  your personal repos. `as-role.sh` resolves the right installation per repo.
- **Org-owned, private** (`--owner-type org --org <login>`) — belongs to the org,
  installs on org repos **only** (no personal repos). Use this only if you want a
  centrally-managed, non-public bot and don't need personal-repo review.

"Public" only means the App is listed and others *could* install it on their own
account; it has no webhook and no server — just an identity whose key you hold —
so someone installing it elsewhere grants access to *you*, not the reverse. Worth
a nod before creating, not a real exposure.

## Run the bootstrap

The helper drives the GitHub App Manifest flow once per role, in turn: it builds
the role's manifest from `roles/<role>/permissions.json` (**no webhook**), serves
a local page that POSTs it to GitHub, catches the redirect, exchanges the
one-time code for the App's credentials, and saves the private key + config in
that role's own config dir.

Run `bootstrap.py` from this skill's directory (the **Base directory** shown when
this skill loads):

```bash
# default: every role not yet set up, user-owned and public:
python3 "<skill-dir>/bootstrap.py"

# a chosen subset:
python3 "<skill-dir>/bootstrap.py" --roles reviewer

# org-only, private (no personal repos):
python3 "<skill-dir>/bootstrap.py" --roles reviewer --owner-type org --org <org-login>
```

Confirm with the operator which roles to create before running it, and, since
the default creates **public** Apps, that they are fine being publicly listed
(harmless, but worth a nod).

For each role it opens your browser to a local page that immediately forwards to
GitHub. The **one step it can't automate** is the click GitHub requires to create
any App: press **"Create GitHub App"**. GitHub redirects back to the local
server, the helper exchanges the code and saves credentials, and moves to the
next role. At the end it prints a JSON list with each role's App slug, config
dir, and **install URL**. A failure stops the run and names the roles it did not
reach.

If the browser doesn't open (headless/SSH), pass `--no-browser` and open the
printed `http://localhost:<port>/` yourself, or forward the port.

## Install the App

Creation does not install an App — an App with no installation can't mint a
token. Open each install URL the helper printed
(`https://github.com/apps/<slug>/installations/new`) and install it on **each
account whose repos that role will work on**, scoped to the repos you want.
⚠️ **Scope this deliberately: the repo list is the only lever you have.** The
reviewer App needs `contents: write` to review at all — GitHub gates resolving a
thread and having a verdict counted on it, with no narrower grant — so a leaked
key can write source on every repo the App is installed on. `SECURITY.md` states
each role's blast radius.

- **Your personal account** — for your personal repos. You install it directly.
- **Each org** — for that org's repos. An org owner approves the install (you can
  self-approve if you're an owner).

Each account is a separate installation; `as-role.sh` resolves the right one per
repo each time the role acts, so install on every account you intend the role to
work on. (An **org-owned** App, if you chose `--owner-type org`, installs on the
org only.)

## Verify

Confirm each role can act on each account you installed it on, through the same
resolver every caller uses. `<repo>` is any repo of that account the App is
installed on:

```bash
"<skill-dir>/../../scripts/as-role.sh" <role> <your-login>/<repo> -- true && echo "ready: personal"
"<skill-dir>/../../scripts/as-role.sh" <role> <org-login>/<repo> -- true && echo "ready: org"
```

A quiet run, apart from the resolver's `as=` line, means setup is complete for
that account. If it reports "not installed on" the account, the install step
didn't land; complete it and retry.

## What got stored

In each role's config dir (default `~/.config/dnbg/<role>/`, override with
`DNBG_<ROLE>_CONFIG_DIR`, the role name upper-cased):

- `private-key.pem` — the App private key (mode 600). **Never commit or share
  it**; it's the bot's full credential. Losing the laptop means deleting the
  App / rotating the key in the App's settings.
- `config.json` — `app_id`, `slug`, `bot_login`, owner. `installation_id` stays
  blank by design: the App can have several installations (org + personal), so
  `as-role.sh` resolves the right one per repo each time.

The directory itself is created `0700`, and the mint refuses to use it if
it is group- or world-writable. That is not belt-and-braces on the `0600` file
mode: a key that cannot be *read* by others can still be *replaced* by anyone who
can write the directory, and the next mint would sign with theirs.

## Keeping the key somewhere other than a file

The plaintext PEM is the default, not the only option — see `docs/configuration.md`'s
"Role Apps' private keys" for the full posture. Two alternatives, both resolved
ahead of the file (shown for the reviewer; every role has its own
`DNBG_<ROLE>_*` set):

- `DNBG_REVIEWER_PRIVATE_KEY` — the PEM itself. With `DNBG_REVIEWER_APP_ID` it
  needs no config dir at all, which is what makes CI and headless runs possible.
  `DNBG_REVIEWER_INSTALLATION_ID` is optional there and saves the
  `/app/installations` round trip, and `DNBG_REVIEWER_SLUG` gives the login the
  watches filter on.
- `DNBG_REVIEWER_PRIVATE_KEY_COMMAND`, or `private_key_command` in `config.json`
  — a command whose stdout is the PEM. This is the hook for any secret manager:

  ```
  op read "op://Private/reviewer/private key"
  pass show reviewer/private-key
  security find-generic-password -s dnbg-reviewer -w
  ```

`bootstrap.py` deliberately does not write to a manager. It writes the file; move
it wherever you want and set the command.

## Repair / rotate

- **Lost or leaked key**: delete the App (or generate a new private key) in the
  App's GitHub settings, then re-run the bootstrap for that role
  (`--roles <role>`) to re-save credentials. `SECURITY.md` has the order.
- **Re-install on more repos**: just adjust the installation's repo access in
  GitHub; no re-bootstrap needed.
- **A permission is missing** (the mint said so, or a call is failing with
  `Resource not accessible by integration`): re-running the bootstrap does
  **not** fix an App that already exists — the manifest is only read at
  creation. Edit the permissions on the App itself, under *Permissions &
  events* at `https://github.com/settings/apps/<slug>`.

  **Then accept the change on every installation, separately.** A permission
  added to an App stays *pending* until each account it is installed on accepts
  it; until then the granted set is the old one and the failure is unchanged, so
  the edit looks like it did nothing. Personal installs you accept yourself; an
  org install needs an org owner.

  Then run **Verify** again. The mint reads what was actually granted, so a quiet run is
  the confirmation — and the App's own settings page is not, since it shows what
  the App *asks* for, which flips the moment you save.
