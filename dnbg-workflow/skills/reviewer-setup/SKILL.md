---
name: reviewer-setup
description: One-time setup creating your own GitHub App, so the `reviewer` skill can post PR reviews under an independent bot identity rather than your personal account — GitHub access only, no cloud infrastructure, no shared secret. Load when asked to set up the reviewer bot or create your reviewer App, when the `reviewer` skill reports no credentials, or to repair or rotate its credentials. The App's private key stays on this machine.
---

# Reviewer setup

This is the **one-time** bootstrap for the local code reviewer. It creates a
per-developer **GitHub App** so the `reviewer` skill can post PR reviews under a
distinct bot identity (e.g. `agent-reviewer-<you>[bot]`) instead of your
personal account. That separate identity is what makes the agent an
*independent* reviewer and what lets it post a binding `--approve` /
`--request-changes` verdict on any PR — including one you authored, which
GitHub forbids when you review as yourself.

Everything runs on **GitHub access only**. The App's private key is generated
during creation, saved on this machine (mode 600), and never leaves it; the
`reviewer` skill signs a short-lived token from it at review time. No cloud
service, no shared secret store.

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
- If credentials already exist (default `~/.config/dnbg/reviewer/config.json`),
  setup is already done — don't re-run unless repairing. Re-running creates a
  *second* App; only do it deliberately.

## Ownership model

A GitHub App's owner determines where it can be installed, and a **private** App
can only be installed on the account that owns it. To review **both** an org's
repos and your **personal** repos with one bot, it has to be installable on two
different accounts — which forces a **public, user-owned** App. That's the
default:

- **User-owned, public** (default) — created under your account; public so it can
  be installed on an org *and* on your personal account. Covers org repos +
  your personal repos. `mint-token.sh` resolves the right installation per repo.
- **Org-owned, private** (`--owner-type org --org <login>`) — belongs to the org,
  installs on org repos **only** (no personal repos). Use this only if you want a
  centrally-managed, non-public bot and don't need personal-repo review.

"Public" only means the App is listed and others *could* install it on their own
account; it has no webhook and no server — just an identity whose key you hold —
so someone installing it elsewhere grants access to *you*, not the reverse. Worth
a nod before creating, not a real exposure.

## Run the bootstrap

The helper drives the GitHub App Manifest flow: it builds a least-privilege
manifest (`pull_requests:write`, `contents:read`, `checks:read`,
`metadata:read`; **no webhook**), serves a local page that POSTs it to GitHub,
catches the redirect, exchanges the one-time code for the App's credentials, and
saves the private key + config locally.

Run `bootstrap.py` from this skill's directory (the **Base directory** shown when
this skill loads):

```bash
# default: user-owned, public — reviews org + personal repos:
python3 "<skill-dir>/bootstrap.py"

# org-only, private (no personal-repo review):
python3 "<skill-dir>/bootstrap.py" --owner-type org --org <org-login>
```

Since the default creates a **public** App, confirm with the operator before
running it (it'll be publicly listed — harmless, but worth a nod).

It opens your browser to a local page that immediately forwards to GitHub. The
**one step it can't automate** is the click GitHub requires to create any App:
press **"Create GitHub App"**. GitHub redirects back to the local server, the
helper exchanges the code, saves credentials, and prints the App slug, the
config dir, and an **install URL**.

If the browser doesn't open (headless/SSH), pass `--no-browser` and open the
printed `http://localhost:<port>/` yourself, or forward the port.

## Install the App

Creation does not install the App — an App with no installation can't mint a
token. Open the install URL the helper printed
(`https://github.com/apps/<slug>/installations/new`) and install it on **each
account whose repos you'll review**, scoped to the repos you want (all repos is
fine; least-privilege is the permission set, not the repo list):

- **Your personal account** — for your personal repos. You install it directly.
- **Each org** — for that org's PRs. An org owner approves the install (you can
  self-approve if you're an owner).

Each account is a separate installation; `mint-token.sh <owner>` resolves the
right one per repo at review time, so install on every account you intend to
review. (An **org-owned** App, if you chose `--owner-type org`, installs on the
org only.)

## Verify

Confirm the reviewer can mint a token for each account you installed on (it
resolves the installation by owner). The minting helper ships with the sibling
`reviewer` skill — it's `../reviewer/mint-token.sh` relative to this skill's
directory (or use the `reviewer` skill's own Base directory):

```bash
"../reviewer/mint-token.sh" "$(gh api user --jq .login)" >/dev/null && echo "ready: personal"
"../reviewer/mint-token.sh" <org-login> >/dev/null && echo "ready: org"
```

A printed token (suppressed above) means setup is complete — the `reviewer`
skill will use it from here on. If it reports "no installations", the install
step didn't land; complete it and retry. Treat a minted token like a password —
don't paste it into chat, logs, or commits.

**Then confirm the permissions actually granted**, per installation. A token
mints fine on a half-permissioned install, so the step above passes while a
review still fails partway through — which is exactly how a missing permission
went unnoticed until it broke `gh pr checks` mid-review:

Reuse the JWT block from `mint-token.sh`, then compare each installation against
`default_permissions` in `bootstrap.py`:

```bash
curl -fsS -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations \
  | jq -r '.[] | "\(.account.login): \(.permissions | to_entries
      | map("\(.key)=\(.value)") | sort | join(" "))"'
```

Every installation must list **every** key in `default_permissions`. A missing
one is not a setup failure you will see here — it surfaces later as
`Resource not accessible by integration` on whichever call needed it. If they
don't match, see **Repair / rotate** below; do not re-run the bootstrap, which
cannot change an App that already exists.

## What got stored

In the config dir (default `~/.config/dnbg/reviewer/`, override with
`DNBG_REVIEWER_CONFIG_DIR`):

- `private-key.pem` — the App private key (mode 600). **Never commit or share
  it**; it's the bot's full credential. Losing the laptop means deleting the
  App / rotating the key in the App's settings.
- `config.json` — `app_id`, `slug`, `bot_login`, owner. `installation_id` stays
  blank by design: the App can have several installations (org + personal), so
  `mint-token.sh <owner>` resolves the right one per repo at review time.

The directory itself is created `0700`, and `mint-token.sh` refuses to use it if
it is group- or world-writable. That is not belt-and-braces on the `0600` file
mode: a key that cannot be *read* by others can still be *replaced* by anyone who
can write the directory, and the next mint would sign with theirs.

## Keeping the key somewhere other than a file

The plaintext PEM is the default, not the only option — see `docs/configuration.md`'s
"The reviewer bot's private key" for the full posture. Two alternatives, both
resolved ahead of the file:

- `DNBG_REVIEWER_PRIVATE_KEY` — the PEM itself. With `DNBG_REVIEWER_APP_ID` it
  needs no config dir at all, which is what makes CI and headless runs possible.
  `DNBG_REVIEWER_INSTALLATION_ID` is optional there and saves the
  `/app/installations` round trip.
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
  App's GitHub settings, then re-run the bootstrap to re-save credentials.
- **Re-install on more repos**: just adjust the installation's repo access in
  GitHub; no re-bootstrap needed.
- **The permission set changed** (bootstrap.py gained an entry, or a review is
  failing with `Resource not accessible by integration`): re-running the
  bootstrap does **not** fix an App that already exists — the manifest is only
  read at creation. Edit the permissions on the App itself, under *Permissions &
  events* at `https://github.com/settings/apps/<slug>`.

  ⚠️ **Then accept the change on every installation, separately.** A permission
  added to an App stays *pending* until each account it is installed on accepts
  it; until then the granted set is the old one and the failure is unchanged, so
  the edit looks like it did nothing. Personal installs you accept yourself; an
  org install needs an org owner. Check what is actually granted — this is the
  authoritative answer, and it is what the App *declares* that misleads:

  Re-run the `/app/installations` check from **Verify** above and compare each
  line against `default_permissions` in `bootstrap.py`. `GET /app` shows what the
  App *asks* for, which flips the moment you save the edit — `/app/installations`
  shows what it actually has.
