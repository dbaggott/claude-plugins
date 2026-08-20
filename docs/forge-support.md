# Forge support

Worth reading before you install. The workflow skills drive the `gh` CLI
throughout — `gh pr`, `gh issue`, `gh api`, `gh search` — deeply enough that
another forge needs its own backend behind a shared contract, not a shim over
the calls below:

- `reviewer` and `reviewer-setup` are built on **GitHub Apps**. The point is an
  identity distinct from your own that can post a verdict on a PR you authored,
  which GitHub forbids from your own account. `reviewer-setup` automates the
  GitHub App **Manifest flow** that `bootstrap.py` drives; GitLab and Bitbucket
  reach the same identity far more cheaply, through project and repository
  access tokens, so the setup is per-forge rather than portable. The reviewer is
  GitHub-only today because only the GitHub backend exists — see
  https://github.com/dbaggott/claude-plugins/issues/149.
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
| GitLab | no | yes | [Next](https://github.com/dbaggott/claude-plugins/issues/149) |
| Bitbucket | no | yes | [Planned](https://github.com/dbaggott/claude-plugins/issues/150) |
| Azure Repos | no | yes | Not planned |
| Anything else, including self-hosted and GitHub Enterprise | no | yes | Unsupported |

Which skills are which is the **Forge** column of [What's in
it](../README.md#whats-in-it) — and read the **Plugin** column beside it, because
*forge-neutral is a property of the skill, not of the plugin shipping it*. The
two neutral skills are obtained differently: `coding-practices` ships in
`dnbg-practices`, which mentions no forge anywhere and installs on its own
(`/plugin install dnbg-practices@dnbg`), while `velocity-tradeoff` ships inside
`dnbg-workflow` because it governs how to size a change and whether to split a
PR — a workflow question. A non-GitHub user therefore gets `velocity-tradeoff`
only by installing the GitHub-coupled plugin, where it then works normally: the
"yes" in the third column above is a per-skill promise, and a `dnbg-workflow`
install on GitLab keeps it.

## What happens on an unsupported forge

**It declines; it does not adapt.** A forge-coupled skill says plainly that the
flow is GitHub-only, names the host it actually found, and hands back to
whatever flow your project already uses. It will not run a `gh` command that
cannot succeed, and it will not translate itself to `glab` or the Bitbucket API
— a half-translated flow is worse than either extreme, and translating properly
is [the per-forge
backends'](https://github.com/dbaggott/claude-plugins/issues/149) job rather than
something to do by halves here.

*What* it checks differs by skill, because the coupled skills don't all act on the
repo you're standing in:

| Skill | Acts on | Declines when |
| --- | --- | --- |
| `git-workflow` | the repo whose tracked file you're changing | that repo's `origin` host isn't `github.com` |
| `issue-workflow` | the repo the issue lives in | the host **in the issue URL** isn't `github.com` — or, for a bare issue number, that repo's `origin` |
| `issue-reviewer` | the repo the issues under review live in | the host **in the issue URL** isn't `github.com` — or, for a bare issue number, that repo's `origin` |
| `reviewer` | a pull request you name explicitly | the *named* repo isn't on GitHub |
| `reviewer-setup` | a GitHub App on your machine | never — no repo is involved |
| `work-summary` | your GitHub account, via `gh search` | never — no repo is involved |

`reviewer`, `reviewer-setup` and `work-summary` deliberately ignore your working
directory, and so do `issue-workflow` and `issue-reviewer` whenever the issue is
named by full URL — which the always-on
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
