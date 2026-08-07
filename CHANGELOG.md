# Changelog

Entries are assembled at release time from the fragments in `changelog.d/`.
Newest first. See `changelog.d/README.md` for how to add one.

Releases before this file existed are recorded in the git history; they were not
tagged, and their versions used a two-component scheme that predates the current
`YYYY.M.N`.

<!-- releases below -->

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

