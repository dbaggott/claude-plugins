# claude-plugins

A Claude Code plugin marketplace, published as `dnbg`. It makes an agent session
work the way a careful colleague would: every change goes through a worktree and
a draft PR, issues are written to survive a cold handoff, and an independent bot
identity reviews the result before a human merges it.

It is **skills** (loaded on demand when they match the task), a short
**always-on rules** file, and two **enforcement hooks** that make the worktree
and issue flows non-optional in the repos you choose.

## What it looks like

**Two sessions on one issue — one resolving it, one reviewing it.** The reviewer
is assigned before any PR exists, so it waits; it sees the draft appear and
holds back, because a draft is the author's signal that the work isn't ready for
anyone's attention yet; it starts the moment the PR is marked ready.

![Two terminal panes side by side. The left session claims the issue, creates a worktree, opens a draft PR, flags a departure from the issue, and asks whether to send it to review. The right session mints a bot token, waits for a PR to appear, holds back while it is a draft, then reviews it and requests changes before approving.](docs/media/demo-resolve-review.gif)

**Filing an issue**, which the gate makes non-optional — an issue written
without the skill is a body the next session can't work from.

![A session's gh issue create being blocked by the check-issue-create hook, then loading the issue-workflow skill, verifying anchors against the tree, and filing an issue whose body carries the defect, a reproduction, a proposed fix, and acceptance criteria.](docs/media/demo-file-issue.gif)

**Turning a week of merged PRs into a recap**, shaped by who's going to read it.

![A session gathering merged PRs and filed issues, reading their descriptions rather than their diffs, asking who the recap is for, and writing a Slack-shaped summary.](docs/media/demo-work-summary.gif)

> These three are **reenactments**. The parts worth showing — a skill deciding
> something, a picker, an agent explaining why it diverged from an issue — are
> Claude Code's own interface and never reach stdout, so no recorder can capture
> them. The dialogue is scripted to match what the skills actually specify; where
> a demo shows command output it is the real thing, and the `BLOCKED` message in
> the second one is produced live by the real hook at record time. The scripts
> are in [`docs/media/`](docs/media/) and the gate demo further down is a
> genuine capture.

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

The `reviewer` pair is the piece with the least in common with the rest — it
exists because GitHub won't let you approve your own PR, and a separate App
identity can. `reviewer-setup` creates that App and keeps its private key on
your machine.

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

**The plugin is the unit you can enable or disable.** Claude Code has no
per-skill switch — the only related setting, `disableBundledSkills`, is
all-or-nothing and applies to Claude Code's own bundled skills rather than to
plugin ones. So what you can adopt on its own is decided by how this project
packages itself, and the table above is that split: each row installs
independently, and anything sharing a row arrives together.

> Three names, deliberately different. The **repo** is `claude-plugins`, a
> **plugin** is e.g. `dnbg-workflow`, and the **marketplace** is `dnbg` — hence
> `dnbg-workflow@dnbg`. Claude Code rejects marketplace names containing
> "claude" as impersonating an Anthropic-official marketplace, which is why the
> marketplace needed a name of its own.

Nothing is enforced until you say where: the hooks block only in repos whose
owner you list in `owners`, and with it empty they never fire. That setting, the
install scopes, and two configurable names are in
[configuration](docs/configuration.md). Requirements — a Claude Code floor and
six command-line tools — are in [requirements](docs/requirements.md).

## Why this rather than rules in a CLAUDE.md

Because a `CLAUDE.md` charges every session for guidance most sessions don't
need, and the plugin's three homes let content sit where it costs least:

| | Triggers | Cost |
| --- | --- | --- |
| **Skill** (`skills/<name>/SKILL.md`) | when the skill's `description:` matches the task | tokens only when loaded |
| **Always-on rule** (`always-on-rules.md`) | unconditionally, every session, every user | tokens on every session × every user |
| **Project `CLAUDE.md`** (in the consuming repo) | unconditionally, but scoped to that repo | tokens when working in that repo |

Most of what a workflow needs is procedural — how to open a PR, how to write an
issue someone else can pick up — and fires on a description match, so it costs
nothing until the moment it applies. The always-on file is kept short on purpose,
and repo-specific facts stay in that repo's own `CLAUDE.md`.

The other half is the part a `CLAUDE.md` cannot do at all: two hooks that
*enforce* the flow rather than advising it, and a reviewer identity that can post
a binding verdict on your own PR.

## What it costs you in tokens

Deliberately little, and that shaped the design rather than being tidied up
afterwards. Five mechanisms, each of which you can check in the skills:

**Issues are written so resolving one costs a read, not a crawl.** The expensive
failure isn't a long issue body — it's a short one that forces the resolver to
open three linked PRs and a design doc before touching code. So `issue-workflow`
pushes the opposite way: paste the schema or the reviewer's concern *inline*
rather than linking it, split cross-references into **Required reading** and
**Related (optional — do not read unless blocked)** so an optional link isn't
paid for by every future reader, cap link-following at **depth 1**, and prefer
one targeted `gh api` fetch over reading a whole PR. Writing that costs the
author minutes once; the alternative charges every resolver the same crawl.

**Waiting is done by shell scripts, not by the model.** A PR that takes an hour
to get reviewed shouldn't cost an hour of wake-ups. `watch-pr.sh` and
`watch-merge.sh` run as background tasks and *block* until something actually
happens, so idle polling never enters the conversation — the model is woken once,
with a result. The poll interval backs off on a shared curve (10s at the start,
30s by the half-hour, a minute by 90 minutes, 5 minutes after), and it counts
laptop-open time, so a closed lid doesn't burn the window.

**Draft status is respected, so you can iterate without spending anyone's
attention.** PRs open as drafts and *you* decide when they go to review. On the
other side, `reviewer` explicitly holds back a discovered draft rather than
verdicting it — a draft is the author's signal to wait, and a review posted over
it spends exactly the attention that signal asked to withhold. Push twenty times
polishing a UI; no review fires until you say so.

**The reviewer reads CI's results instead of re-running them.** It never waits
for CI and never polls it, and it doesn't re-run the project's test suite —
whole, per-file, or sweeping for flakes. The first reason is correctness, not
cost: a local run reproduces the *author's* environment rather than CI's, so on a
load-sensitive defect your machine wins the race a loaded runner loses and every
green run argues "flaky, ignore it" — the wrong verdict, reached expensively.
Being cheaper is the second effect, not the justification.

**Content lives where it costs least.** That's the table
[above](#why-this-rather-than-rules-in-a-claudemd): skills load only when their
description matches the task, and `always-on-rules.md` — the one file charged to
every session of every user — is kept short on purpose. New guidance has to argue
its way in, and a skill is almost always the right home.

## Which forges

**GitHub is supported.** GitLab and Bitbucket are
[planned](https://github.com/dbaggott/claude-plugins/issues/21); everything else
is unsupported. The forge-neutral skills — `coding-practices` and
`velocity-tradeoff` — work anywhere regardless.

On an unsupported forge a coupled skill **declines and says so**, naming the host
it found, rather than half-translating itself to another CLI. The per-forge
matrix, what each skill checks, and why the coupling isn't papering-over-able are
in [forge support](docs/forge-support.md).

## What it runs on your machine

Installing `dnbg-workflow` means **it runs shell scripts on your machine** —
that is what a Claude Code hook is. Four of them fire automatically once the
marketplace is trusted: two inject the always-on rules (at session start, and
again per subagent, because session-start output does not reach subagents), and
two are the gates that block edits outside a worktree and unguarded
`gh issue create` calls.

![A session being blocked from editing a tracked file in the main checkout, running the git worktree add the block message prints, retrying the edit successfully, then reading the reviewer bot's verdicts on a real pull request](docs/media/demo-gate.gif)

Unlike the three above, that one is a genuine capture: real output from
`check-worktree.sh`, from `git`, and from the GitHub API.

They make **no network calls**, write no files, and hold no credentials, and
**nothing here updates itself** — what you install is what runs until you update
it deliberately, so reading
[`dnbg-workflow/hooks/`](dnbg-workflow/hooks/) once is a review that stays valid.

[`SECURITY.md`](SECURITY.md) is the full account: what each hook sees, the one
place a transcript is read and why, what the reviewer bot's key can do, and why
the gates are workflow guardrails rather than a security boundary.

## Who maintains it

One person, opinionated on purpose. This is a personal artifact published because
it might be useful to someone else — not a project seeking governance, and not
one with a roadmap it owes anyone.

Bug reports, portability findings, tests for untested branches, and
documentation corrections are all welcome. So are new **knobs** that leave the
current behavior as the default. Swapping one default for another is not:
worktree-then-draft-PR, never merging your own work, and fragments-drive-releases
are the product rather than incidental choices. [`CONTRIBUTING.md`](CONTRIBUTING.md)
has the detail, and an issue first is always cheaper than a declined PR.

`dnbg` is the maintainer's initials — deliberate personal branding rather than an
acronym you are failing to decode.

## Documentation

| | |
| --- | --- |
| [Requirements](docs/requirements.md) | Claude Code floor, the six CLI tools, platforms |
| [Configuration](docs/configuration.md) | Install scopes, `owners`, the two configurable names, the reviewer key |
| [Forge support](docs/forge-support.md) | Per-forge matrix, and what declining looks like |
| [Releases](docs/releases.md) | Updating, auto-update, CalVer, installing a specific version |
| [Security](SECURITY.md) | Threat model, what the hooks see, reporting a vulnerability |
| [Contributing](CONTRIBUTING.md) | Scope, the fragment rule, running CI locally |
| [For maintainers](docs/maintainers.md) | Repo layout, where new content goes, forks, regenerating the demo |

## License

[Apache-2.0](LICENSE).
