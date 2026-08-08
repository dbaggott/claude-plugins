# Changelog

Entries are assembled at release time from the fragments in `changelog.d/`.
Newest first. See `changelog.d/README.md` for how to add one.

Releases before this file existed are recorded in the git history; they were not
tagged, and their versions used a two-component scheme that predates the current
`YYYY.M.N`.

<!-- releases below -->

## dnbg-workflow 2026.8.10 — 2026-08-08

Both background watchers now measure time in **laptop-open seconds** and share
one poll curve.

- **A suspended machine no longer burns a watch.** Closing the lid overnight used
  to retire the merge watcher's whole window, so it woke to an already-blown
  deadline and reported "watched the full window, no merge" having never once
  looked. Suspended time is now discounted from both the window and the poll
  interval, and a watch comes back at the 10-second floor — fastest at exactly
  the moment you have reopened the machine.
- **New poll curve, shared by every watch** (merge, first review, PR-appears):
  10s at the start, easing to 30s over half an hour, a minute by the 90-minute
  mark, then 5 minutes flat. Whatever you are waiting for usually happens in the
  first few minutes and nearly always within the hour, so the wait is short when
  it matters and cheap when it doesn't. Tunable via `POLL_CURVE`.
- **The merge watcher is a real script** (`scripts/watch-merge.sh`) rather than
  51 lines of shell inlined in `git-workflow`'s prose, so `shellcheck` covers it
  and `tests/watch-merge.bats` pins every branch — including a payload that
  stops parsing, and a blocked-but-still-running check, neither of which had any
  coverage before.
- **A short outage no longer ends a watch.** Declaring the watch broken needs
  both a run of failed ticks and a few minutes of awake time, because a failure
  resets the poll interval to its 10-second floor — so ten ticks was only ~100
  seconds. Waking from suspend resets to the floor too, which made
  lid-open-then-reconnect the likeliest way to lose a watch on a healthy PR.
- **It reports a `result=` line for every outcome**, where the inline version
  printed one only for timeouts and total failures and left the caller to infer
  the rest from state fields. `result=UNREACHABLE` is replaced by
  `result=ERROR reason=<source>`, which trips as soon as a source has failed
  repeatedly instead of burning the entire window first.


## dnbg-workflow 2026.8.9 — 2026-08-08

The `reviewer` skill now spends its budget where findings actually come from.

Behavior changes, effective as soon as the plugin updates:

- **The reviewer no longer re-runs the project's test suite.** A local run
  reproduces the author's environment rather than CI's, so on a timing- or
  load-sensitive defect it argues "flaky, ignore it" — the wrong verdict. CI
  verifies and enforces green; the reviewer reads the check results instead.
- **Instrumented reproduction of one doubted claim is still permitted**, and is
  explicitly triggered by doubt about a specific claim rather than by a red
  check — the most valuable probes tend to run while CI is green.
- **The reviewer never waits for or polls CI.** It reads whatever check state
  exists when it looks, once, and proceeds.
- **It reads less of each file**: diff hunks for a `MODIFIED` file, and no
  re-fetch of an `ADDED` one (the diff already carries it), fetching whole files
  only when the hunks don't carry enough context.
- **Re-reviews read `compare/<last-reviewed-sha>...<new-head>`** rather than the
  full PR diff again — cheaper, and exactly the changes the prior verdict didn't
  cover.

Judging test coverage by *reading* tests is unchanged; the restriction is
narrowly about executing them.


## dnbg-workflow 2026.8.8 — 2026-08-08

The reviewer now re-posts its verdict whenever new commits land past the SHA its
standing approval is attached to, even when the verdict is unchanged, naming the
SHA in the body. Previously it stayed silent on a change it judged trivial, which
left the approval pointing at an older commit while GitHub's merge box showed an
unqualified green check — and left the author's watcher waiting for a signal the
reviewer had been told not to send.

Both skills now answer "is HEAD approved?" by checking that the latest *verdict*
on the PR is an `APPROVED` attached to `headRefOid` — not by inferring it from the
repo's *Dismiss stale pull request approvals* setting. That setting is meaningless
where no approval is required (the default on a personal repo that gates on CI),
so the inference produced confidently wrong answers in both directions. Where
approvals are required, `reviewDecision` remains the primary source. Nothing in
either skill reads branch protection any more — one less call that needs admin.

`git-workflow` no longer reports a cause for `mergeStateStatus: BLOCKED` without
reading one: an unresolved review thread is now listed alongside a failing check
and a dismissed approval, and it is a hard blocker wherever
`required_conversation_resolution` is on.


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

