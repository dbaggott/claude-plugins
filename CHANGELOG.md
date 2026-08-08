# Changelog

Entries are assembled at release time from the fragments in `changelog.d/`.
Newest first. See `changelog.d/README.md` for how to add one.

Releases before this file existed are recorded in the git history; they were not
tagged, and their versions used a two-component scheme that predates the current
`YYYY.M.N`.

<!-- releases below -->

## dnbg-workflow 2026.8.7 — 2026-08-08

The PR/issue watcher no longer reports a broken watch as a quiet one. If a poll
source fails repeatedly it emits `result=ERROR reason=<source>`, and both skills
now stop and tell you to check `gh auth status` rather than re-arming into the
same failure forever. Previously a watch that never once reached GitHub ran out
its window and printed the same `result=IDLE` a genuinely calm PR prints.

A second, quieter version of the same bug is fixed too: the thread-replies query
ended in `|| echo 0`, so a failure read as "no new replies" while the main poll
kept succeeding — the watch looked healthy and was partly blind.

Polling is now a curve rather than a fixed 30s. It starts at 10s so a reply lands
almost immediately, holds 30s for an hour after the last activity, then backs off
to 15 minutes once nothing is happening. A 6-hour watch drops from roughly 1440
API calls to about 294, while the first minute gets faster.

The reviewer's issue-scoped wait — used when one agent implements an issue and
another reviews it — now runs on the same script in `--issue` mode instead of its
own fixed two-minute loop, so it gets the curve and the failure reporting too.


## dnbg-workflow 2026.8.6 — 2026-08-08

The reviewer bot's credentials move from `~/.config/agent-reviewer/` to
`~/.config/dnbg/reviewer/`, so everything this marketplace writes to disk now
lives under one `dnbg` directory. The override environment variable is renamed
`REVIEWER_CONFIG_DIR` -> `DNBG_REVIEWER_CONFIG_DIR`.

The GitHub App itself is **not** renamed. It stays `agent-reviewer-<your-login>`,
because it is your identity on other people's pull requests rather than
something this marketplace owns.

## Migration
If you have already set up the reviewer bot, move its directory:

    mkdir -p ~/.config/dnbg && mv ~/.config/agent-reviewer ~/.config/dnbg/reviewer

Nothing reads the old location any more. There is no compatibility fallback, and
none is needed: `mint-token.sh` already fails with `reviewer bot is not set up
(no credentials in <dir>)` naming the directory it searched, so an unmigrated
install says exactly what is wrong instead of failing silently.

If you set `REVIEWER_CONFIG_DIR`, rename it to `DNBG_REVIEWER_CONFIG_DIR`.


## dnbg-practices 2026.8.1 — 2026-08-07

First release. `coding-practices` now ships as its own plugin, so it can be
installed on its own — no hooks, no `gh`, no forge assumptions, works anywhere.

Previously it was only available inside `dnbg-workflow`, which meant taking two
enforcement hooks and five GitHub-specific skills to get it.


## dnbg-workflow 2026.8.5 — 2026-08-07

`coding-practices` and `work-summary` have moved out into their own plugins,
`dnbg-practices` and `dnbg-work-summary`. This plugin now carries the GitHub
workflow: `git-workflow`, `issue-workflow`, `velocity-tradeoff`, `reviewer` and
`reviewer-setup`, plus the two enforcement hooks.

`prototype-velocity` is renamed `velocity-tradeoff`. The old name described a
project stage; the skill's own framing is that the trade is a ratio — blast
radius, reversibility, time-to-notice, test coverage, users — and not a fact
about the project.

## Migration
**Any repo whose `CLAUDE.md` opts in must change `dnbg-workflow:prototype-velocity`
to `dnbg-workflow:velocity-tradeoff`.** The old name does not error; it silently
stops loading, so the opt-in simply stops taking effect.

If you want `coding-practices` or `work-summary`, install them:

    /plugin install dnbg-practices@dnbg
    /plugin install dnbg-work-summary@dnbg

or `/plugin install dnbg-all@dnbg` for everything. This plugin does **not**
depend on them — the workflow skills stand alone, and their few references to
coding standards are optional pointers rather than requirements.


## dnbg-work-summary 2026.8.1 — 2026-08-07

First release. `work-summary` now ships as its own plugin. It has no
dependencies on the other skills and installs no hooks.


## dnbg-all 2026.8.1 — 2026-08-07

First release. Installs `dnbg-practices`, `dnbg-workflow` and
`dnbg-work-summary` — everything in this marketplace, in one command.

Its dependencies are unversioned, so it tracks whatever version of each sibling
the marketplace provides rather than pinning them.


## dnbg-workflow 2026.8.4 — 2026-08-07

Only `github.com` remotes are covered by the enforcement hooks now. Previously
the owner match ignored the remote's host, so listing a GitHub org also gated a
same-named org on GitLab or Bitbucket — blocking edits there while every skill
instructed the agent to run `gh` commands that cannot work against that remote.

Also fixes a remote with an explicit port (`ssh://git@github.com:22/owner/repo`)
parsing the port as the owner, which made a covered repo read as uncovered and
silently lose its gate.

## Migration
If you left `owners` empty because you work on a non-GitHub host, you no longer
need to — set it to the GitHub accounts you want enforced and non-GitHub remotes
are ignored regardless. GitHub Enterprise hosts are *not* covered; that is
deliberate, since the skills' `gh` usage has not been verified against them.


## dnbg-workflow 2026.8.3 — 2026-08-07

The plugin no longer updates itself. `update-marketplace.sh` has been removed,
along with its session-start hook — the plugin now makes no network access at
all, and what you install is what runs until you update it.

Claude Code's own per-marketplace auto-update does the same job and does it
sooner: it checks after each session starts rather than throttling to once every
four hours.

## Migration
Nothing breaks, but **you will stop receiving updates automatically** unless you
turn them on. In `/plugin` → Marketplaces → dnbg → Enable auto-update. The
removed hook also left a throttle stamp behind; delete it if you like:

    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/dnbg-workflow/last-update"


## dnbg-workflow 2026.8.2 — 2026-08-07

The PR watcher used by `git-workflow` is now the same hardened script `reviewer`
uses, moved to `scripts/watch-pr.sh` and shared. The author side previously
inlined its own loop, which polled for a review on the current head SHA — right
after pushing a fix, wrong after replying in threads, where nothing moves and
the watcher matched the review it had already handled.

`git-workflow` also gains runnable commands for enumerating unresolved review
threads and for replying in a thread and resolving it, replacing prose that was
easy to skip.


## dnbg-workflow 2026.8.1 — 2026-08-07

Plugin versions move to `YYYY.M.N` — year, unpadded month, Nth release of that
plugin that month. Each plugin now carries its own counter, and releases are
driven by changelog fragments rather than firing on every merge.

Releases are now tagged (`{plugin}--v{version}`) and published as GitHub
Releases with notes assembled from `changelog.d/`.

## Migration
The previous two-component scheme (`2026.4`) was not semver-parseable, which
meant no tag it produced could ever be selected by plugin dependency
resolution. Nothing is required of users. Anyone scripting against the old
two-component version should expect three components from now on.

