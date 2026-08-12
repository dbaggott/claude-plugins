# Changelog

Entries are assembled at release time from the fragments in `changelog.d/`.
Newest first. See `changelog.d/README.md` for how to add one.

Releases before this file existed are recorded in the git history; they were not
tagged, and their versions used a two-component scheme that predates the current
`YYYY.M.N`.

<!-- releases below -->

## dnbg-workflow 2026.8.30 — 2026-08-12

`issue-workflow` splits into `references/creating.md` and
`references/resolving.md`, with `SKILL.md` keeping the host check, the
maintenance sweep, the reference conventions, and a router. Filing an issue and
resolving one share almost nothing, so each session now loads roughly half of
what it used to: a filer drops the 2,600 words on claiming and freshness probes,
a resolver the 1,200 on writing a good body.


## dnbg-practices 2026.8.3 — 2026-08-12

Skill descriptions are shorter. A description loads into every session whether or
not its skill fires, and these had grown into summaries of their own contents —
listing mechanisms a reader only needs *after* deciding to load. They now carry
identity, triggers, and skips only, and nothing about when a skill loads has
changed.


## dnbg-workflow 2026.8.29 — 2026-08-12

Skill descriptions are shorter. A description loads into every session whether or
not its skill fires, and these had grown into summaries of their own contents —
listing mechanisms a reader only needs *after* deciding to load. They now carry
identity, triggers, and skips only, and nothing about when a skill loads has
changed.


## dnbg-work-summary 2026.8.3 — 2026-08-12

Skill descriptions are shorter. A description loads into every session whether or
not its skill fires, and these had grown into summaries of their own contents —
listing mechanisms a reader only needs *after* deciding to load. They now carry
identity, triggers, and skips only, and nothing about when a skill loads has
changed.


## dnbg-workflow 2026.8.28 — 2026-08-12

`reviewer` sheds ~230 words of prose that recorded its own development rather
than instructing: how the issue wait's predecessor `sleep 120` loop behaved, a
rate-limit comparison the text itself called "not the one carrying the decision",
and two notes restating what a test's failure message already says. Every rule
they surrounded is unchanged.


## dnbg-practices 2026.8.2 — 2026-08-12

`coding-practices` now applies "what a comment must not carry" to prose that
instructs an agent — skill files, always-on rules, `CLAUDE.md` — and loads when
you are authoring that prose. The bar was already right; it just read as
code-only, and the skill's own trigger skipped "non-code questions", so neither
reached the sessions where skill prose gets written.


## dnbg-workflow 2026.8.27 — 2026-08-12

`reviewer`'s issue-scoped mode moves to `references/issue-mode.md`, leaving a
pointer in `SKILL.md`. It was 2,124 words — 29% of the skill — that a PR-scoped
review loaded and never used. Draft handling stays in `SKILL.md`, since a draft
the operator names directly is a PR-scoped concern and arming the watch with
`--was-draft` is the only way it ever reports `READY`.


## dnbg-workflow 2026.8.26 — 2026-08-12

`reviewer` no longer files style nits as inline comments. An inline comment is a
review thread, and a thread blocks the merge outright wherever
`required_conversation_resolution` is on — so a nit filed on a line held the
merge hostage while the review body called it non-blocking. The skill now tests
inline-vs-body on "would you hold the merge for it" rather than "does it request
action", ties filing a thread to `--request-changes` so the verdict and the
threads agree, forbids describing an open thread as non-blocking, and says to
resolve a nit-thread that turns out to be the last blocker.


## dnbg-workflow 2026.8.25 — 2026-08-11

The `check-worktree` hook's block message now names the file and the retry path
correctly when the edited path reaches the repo through a symlink — on macOS,
anything under `/tmp`, and any symlinked home or project directory. Previously
both stayed absolute, so the retry path the message told you to use was the
worktree root joined to a second absolute path, a location that could not exist.

The gate itself is unchanged: a tracked file in a main checkout was blocked
before and still is. Only the text you act on after the block was wrong.


## dnbg-workflow 2026.8.24 — 2026-08-11

`reviewer-setup` now points at `docs/configuration.md` for the reviewer key's
sources, rather than at a README section that no longer exists. The skill relays
that pointer to you when it sets the bot up, so the stale one was reaching users.


## dnbg-workflow 2026.8.23 — 2026-08-10

New always-on rule: when a script, hook, or procedure the plugin ships doesn't
cover your case, the agent finishes the task the narrow way, then tells you what
didn't fit and offers to report it upstream.

Filing is never agent-initiated. An issue against this project is published
under *your* GitHub identity to a repo you don't control, so it happens only if
you ask for it, is written from the generic case with nothing personal or
session-specific in it, and is shown to you in full for approval before it is
submitted. With no user present to ask, nothing is filed.

The rule also states two things that were previously implicit: a hook that
blocks you is working as intended and should be satisfied rather than routed
around, and the installed plugin copy under `~/.claude/plugins/` is never a
place to edit — those edits are unreviewed and are destroyed by the next update.


## dnbg-workflow 2026.8.22 — 2026-08-10

The always-on rules now reach subagents, not just the main conversation.

`SessionStart` output — which is how this plugin injected its rules — reaches the
main loop and nothing else, so any subagent you spawned had never been told to
work in a worktree, to reference issues by full URL, or about any configuration
override you had set. A new `SubagentStart` hook injects the same rules into each
subagent.

This is a behavior change on an installed machine: subagents now see the rules
and act on them, and each spawn costs the tokens the rules occupy.


## dnbg-workflow 2026.8.21 — 2026-08-10

The workflow skills now state that they are GitHub-only and decline cleanly on
another forge, instead of running `gh` commands that cannot work and surfacing a
cascade of confusing errors.

`git-workflow` reads `git remote get-url origin` before it acts, and on a
non-`github.com` host it says so, names the host it found, and hands back to
whatever flow your project already uses — it does not attempt a `gh` call and
does not translate itself to another forge's CLI. A repo with no `origin` is not
treated as a decline: it makes no forge claim either way, so the flow proceeds
rather than guessing a host.

`issue-workflow` resolves the host from the issue itself. An issue named by full
URL carries its own host, and that is what decides — the working directory is
not consulted at all, so picking up a GitHub issue from a GitLab checkout works
normally. Only a bare issue number, or creating an issue in place, falls back to
reading `origin`; the no-`origin` behavior above applies on that route.

`reviewer` judges the repo holding the PR you named, not your working directory,
and `reviewer-setup` is not repo-scoped at all — both keep working when you
review a GitHub PR from a checkout of some other forge's repo.

`velocity-tradeoff` is unaffected on every host. It ships in this plugin but
mentions no forge, and declining is decided per skill rather than per plugin.

The README now carries a support matrix naming every forge — GitHub supported,
GitLab and Bitbucket planned, Azure Repos not planned, everything else including
self-hosted and GitHub Enterprise unsupported — and states which plugin ships
each skill and whether that skill needs a forge at all.


## dnbg-work-summary 2026.8.2 — 2026-08-10

`work-summary` now states that it recaps GitHub work specifically, and that it
is scoped to your GitHub account rather than to any repository.

The practical effect is a guarantee rather than a restriction: asking for a
recap of your GitHub week while sitting in a GitLab checkout — or in no repo at
all — is a supported request, and the skill will not consult
`git remote get-url origin` to decide whether to run.


## dnbg-workflow 2026.8.20 — 2026-08-10

The issue-scoped wait now wakes on PRs that reference an issue without a closing
keyword, and the claim check now sees them too.

Both asked "which PRs belong to this issue?" using only
`closedByPullRequestsReferences`, which lists PRs carrying a **closing keyword**
and nothing else. `git-workflow`'s multi-repo rule has exactly one sibling close
an issue while the rest merely reference it, so the narrow source misses the
shape that rule mandates.

**`reviewer`'s issue-scoped wait** (`watch-pr.sh --issue`) polls the issue
timeline's cross-references alongside the closing references. Previously a real
resolving PR that linked the issue in prose never woke the watch: it ran its full
window, reported `IDLE`, and the deadline path then presented it as a probably
wrong issue number — a diagnosis that could not be confirmed, because the issue
resolved fine. Meanwhile the unreviewed PR could merge.

**`issue-workflow`'s claim check** gained the same second source. Without it, an
in-flight multi-repo change reads as unclaimed the moment its closing PR merges,
and a second session starts work already half-shipped.

New `ERROR reason=issue-timeline` and `issue-timeline-shape` results report the
timeline source going blind, rather than letting partial blindness present as a
quiet issue. They are counted separately because they need different remedies: a
failed fetch is transient and earns a grace period, while a payload that stopped
parsing is a schema change and is reported as soon as it repeats.

`tests/coupling.bats` now pins both sites against `reviewer`'s discovery set, so
neither can be narrowed alone. A discovery source a site deliberately skips must
say so inline (`PR-SOURCE-EXEMPT: <source> — <reason>`); `gh search prs` is
exempt at both, since the timeline is authoritative with no index lag, so search
could only ever show the same PR later.

## Migration
`watch-pr.sh --issue` takes a new optional `--exclude=<url,url,...>` of PR URLs
already triaged as not-resolving. It is not optional in practice when re-arming:
a mention-only PR left open satisfies the timeline source on **every** tick, so a
wait re-armed without it wakes immediately and repeatedly. Carry the list forward
across re-arms, and use full PR URLs — the timeline spans repos, where bare
numbers collide. Entries may be separated by `, ` as well as `,`; surrounding
whitespace is trimmed.

Only the `--exclude=<value>` form is accepted. A valueless `--exclude`, or an
`--exclude` passed without `--issue` (where nothing reads it), is refused with
`result=ERROR reason=bad-args` rather than ignored.


## dnbg-workflow 2026.8.19 — 2026-08-10

Two of the workflow's mechanical choices are now configurable from `/plugin`,
alongside `owners`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `worktree_path` | `.worktrees` | Repo-relative directory worktrees are created in |
| `claim_label` | `assigned:agent-session` | Label an agent session applies when it claims an issue |

Set one and the session-start hook prints a short note saying so, which the
skills read as overriding the defaults they spell out; the `check-worktree` block
message names the configured directory too, so the `git worktree add` it hands
you is runnable as printed. Set neither and nothing changes — no note is printed,
and the skills' literal `.worktrees/` and `assigned:agent-session` stand.

Both values are validated, and a rejected one falls back to the default with the
reason printed at session start rather than being silently ignored. A worktree
path has to stay inside the repo (no absolute path, no `~`, no `..` segment), and
a claim label has to start with `assigned:` — the check for someone *else's*
claim matches that whole namespace, so a label outside it would make your claims
invisible to other tools and theirs invisible to you.

What stays fixed, deliberately: PRs always open as drafts, the send-to-review
picker and its option order, the `[<branch-name>]` sibling PR title tag, and
"only a human merges".


## dnbg-workflow 2026.8.18 — 2026-08-09

`git-workflow` described `watch-pr.sh`'s argument handling wrongly in three
places. All three are corrected; no behaviour changed.

**The watch-guard comment** in "Watching for the first review" said the script
fails quietly on either argument being blank, and that a blank head means its
commit check "can never fire for the whole window". Neither half holds: a blank
`<last_head>` is accepted and self-heals from the first observed HEAD, and a
blank `<bot_slug>` is refused outright with `result=ERROR reason=bad-args`. The
guard is unchanged — a blank value means the `gh` call above it failed — but its
stated rationale now matches what the watcher does.

**`result=ERROR reason=bad-args` now has its own entry** in the result-line
table, which previously routed every `ERROR` to "check `gh auth status`, do not
re-arm". `bad-args` needs the opposite remedy: nothing failed, the watch refused
to start, so fix the argument and re-spawn.

**The re-arm step now says to pass the full 40-character `headRefOid`.** An
abbreviated SHA is how a watch actually earns a `bad-args` here — the spawn's
guard tests for blankness, and an abbreviation is not blank — so it slips
through to the watcher, which refuses it.


## dnbg-workflow 2026.8.17 — 2026-08-09

`watch-pr.sh` now refuses an abbreviated `<last_head>` instead of reporting a push
that never happened. The value is compared as a string against the 40-character
`headRefOid` GitHub returns, so a short SHA could never match it — two watches
armed with 7-character SHAs both returned `result=COMMITS` within seconds of
starting, each naming the full SHA as `new_head` with nothing having been pushed.
`reviewer` read that as a delta to re-review and `git-workflow` read it as the
author pushing; neither could tell it from the real thing.

Anything that is neither empty nor 40 lowercase hex characters now reports
`result=ERROR reason=bad-args` and exits 0, matching the existing empty-slug bail.
Empty is still accepted and still self-heals from the first observed HEAD, and
`--issue` mode (which never reads the argument) is unaffected.

## Migration
Callers passing a short SHA must switch to the full one —
`gh pr view <n> --repo <repo> --json headRefOid --jq .headRefOid`. Both skills
already do; the `reviewer` skill now says so explicitly at the spawn site.


## dnbg-workflow 2026.8.16 — 2026-08-09

`issue-workflow` now claims an issue with `assigned:agent-session` instead of
`assigned:claude-code`, and the claim comment names the claiming session.

The label rename makes the mark match what it actually communicates — an agent
session took this issue, not a particular product. The skill already described
the `assigned:*` namespace as open to any claimant ("another agent, a bot, a
teammate's tooling"); the label it applied itself was the one thing that
contradicted that.

The claim comment now reads `Claimed by an agent session (<id>).`, where `<id>`
is the first 8 characters of `CLAUDE_CODE_SESSION_ID`. That turns a question the
skill previously called "mechanically indistinguishable" — is this claim my own
earlier mark, or a sibling session's? — into a comparison against the latest
claim comment. Only an exact match licenses proceeding, so any id that can't be
positively accounted for still stops and asks. Where no session id is exported
the comment says `(id unavailable)` and the old judgement applies.

The practical gain is unattended runs, which previously had to stop on *every*
own-account claim, including their own.

Behavior changes, effective as soon as the plugin updates:

- **New claims use the new label.** An issue claimed from now on carries
  `assigned:agent-session`; `gh label create --force` in the claim block creates
  it on first use in any repo.
- **Claims already on your issues keep working, and need no cleanup.** The
  pickup check matches the `assigned:*` prefix rather than an enumerated list,
  so an issue carrying `assigned:claude-code` is still detected as claimed.
  Verified against a real issue in this repo, not by inspection. There is no
  relabeling script and none is needed.


## dnbg-workflow 2026.8.15 — 2026-08-09

The reviewer bot's private key can now come from a secret manager or the
environment instead of a plaintext file, and its directory is hardened.

The key is resolved from the first source that yields one:

1. `DNBG_REVIEWER_PRIVATE_KEY` — the PEM itself.
2. `DNBG_REVIEWER_PRIVATE_KEY_COMMAND`, or `private_key_command` in
   `config.json` — a command whose stdout is the PEM.
3. `~/.config/dnbg/reviewer/private-key.pem` — the existing default, unchanged.

Route 2 is one hook that reaches every manager without this project integrating
with any of them (`op read`, `pass show`, `security find-generic-password -w`,
`secret-tool lookup`, `vault kv get`, `sops -d`). Route 1 stands alone: paired
with `DNBG_REVIEWER_APP_ID`, no config file or PEM needs to exist, which makes
running the reviewer in CI possible for the first time.

Three properties, each with a test:

- **The key command is read only from user config or the environment, never from
  a repository.** Nothing reads config from the working directory. This is what
  makes the hook safe — the command grants no capability someone who can already
  write `~/.config` lacked, and that argument fails the moment a cloned repo can
  supply the value.
- **A key from route 1 or 2 is never written to disk.** It is passed through a
  pipe rather than a temp file, so nothing can be stranded by a crash or an
  uncatchable signal — if you keep the key in a vault, the tool must not quietly
  materialise it in `/tmp` on every mint. Route 3 is unchanged and still hands
  `openssl` the path it already had, so the default setup gains no new
  dependency.
- **A group- or world-writable config directory or key file is refused**, the way
  `ssh` refuses an over-permissive private key.

Behavior changes, effective as soon as the plugin updates:

- **`mint-token.sh` refuses to run against a loose config directory.** If yours
  is group- or world-writable it will now stop and tell you, rather than signing
  with whatever key it finds. Fix with `chmod go-w ~/.config/dnbg/reviewer`.
- **`bootstrap.py` sets the config directory to `0700`** on every run, including
  over an existing directory.

The plaintext file remains the default, and the README now says so explicitly —
with the reasoning — rather than leaving it as an unstated convention.


## dnbg-workflow 2026.8.14 — 2026-08-09

Follow-ups to the watcher tracing, all from review of the change that added it.

- **`git-workflow` now handles a watcher that returns nothing.** Both of its watch
  loops — the review watch and the merge watch — had no branch for a missing
  `result=` line, so a killed watcher was indistinguishable from a quiet one. That
  matters most on the merge watch, which runs for hours while you are away: a kill
  there could swallow the merge and skip the post-merge cleanup entirely. Both now
  say to re-read the PR's real state rather than trusting the watcher's silence,
  and the spawn instructions point at the trace file that says which of the three
  deaths occurred. `reviewer` already had this branch; the two are now consistent.
- **A watcher's trace now records its own arguments.** `START` named only the
  script and pid, so a stray trace showed that *a* watch had died but not which PR
  it was watching — the one thing a post-mortem across several kills needs.
- **The bats reaper verifies a process is still ours before killing it.** It fires
  at pids that are routinely already dead, and `kill` on a corpse is a harmless
  no-op only until the number is recycled — after which it kills a stranger,
  possibly in another session. Reuse is not plausible at observed pid churn, but
  the guard costs one `ps` and removes the failure mode rather than resting on
  that arithmetic.


## dnbg-workflow 2026.8.13 — 2026-08-09

**The issue-creation gate no longer blocks commands that merely talk about
creating an issue.**

It decided what a command did by grepping the whole command string, so the phrase
matched wherever it appeared — including inside a quoted argument or a heredoc
body, where it is text rather than a command. Any command whose payload discussed
issue creation was blocked, and the payloads most likely to do that are the ones
written while working on this repo: review bodies, commit messages, issue text. It
blocked a reviewer bot from posting a review *about this hook*.

The gate now requires the phrase to be in command position — the start of a line,
or after `;`, `&&`, `||`, `|` or `(` — and masks quoted spans first. Genuine
invocations are unaffected, including ones that follow another command.

Heredocs are why command position is the load-bearing half: a heredoc body is not
quoted, so masking alone would have left the commonest case still blocked.

One accepted limitation: a heredoc line that *begins* with the phrase still
matches. A false negative only means a skill went unloaded, which the workflow's
own claim check largely covers; a false positive blocks real work and points you
at a skill irrelevant to it.


## dnbg-workflow 2026.8.12 — 2026-08-09

The PR and merge watchers can now explain their own death, and three ways a watch
could go silently blind are fixed.

**Tracing, on by default.** Both watchers now record a line per poll, per signal,
and at exit, to `${TMPDIR:-/tmp}/dnbg-watch/<script>-<pid>.log`, swept after three
days. `WATCH_LOG=<path>` redirects it and `WATCH_LOG=off` turns it off, after
which nothing is installed and nothing is spent.

It defaults ON rather than being a knob, because the failure it exists to catch
is intermittent and unreproducible — it has happened four times, never on demand.
A knob somebody has to remember to set *before* a random failure is off exactly
when it matters, so the feature would have shipped and never once fired.
Defaulting also covers every caller, including spawn sites written later, which
wiring the knob into today's callers would not.

It exists because a watch that is killed leaves no evidence anywhere else:
its one result line is written at exit, so a killed watch produces an empty output
file, and macOS records ordinary process signals nowhere. Three outcomes separate
the causes, and the third is an absence — a heartbeat with no `SIGNAL` and no
`EXIT` line means SIGKILL or a process-group teardown.

**Behavior change on the shipped path:** a nap is now a backgrounded `sleep` that
is waited on, rather than a foreground one. Bash defers a trap until the running
foreground command finishes, so a foreground nap swallowed a `SIGTERM` for up to a
full interval — five minutes at the cap — and where a `SIGKILL` followed, the
handler never ran at all. This applies whether or not you enable tracing.

Fixes, each of which previously left a watch running and reporting something
plausible but wrong:

- **Replies behind a page of older comments were invisible.** The comments query
  took the endpoint's default ordering, which is oldest-first and caps at 30 — so on
  a PR with more than 30 inline comments every new reply sat on a page the watch
  never fetched. It saw only history, never woke, and idled out looking healthy.
  Most likely to bite on a busy PR with several reviewers. It now asks for
  newest-first, which is both correct and one request per poll regardless of how
  long the thread gets.
- **A payload that parsed but had lost `.state` passed the shape gate.** An API
  error body is well-formed JSON, so it was accepted with an empty state that
  matched neither MERGED nor CLOSED; the watch ran its whole window against it and
  reported `IDLE` on a PR that had already closed. `isDraft` is now checked too — a
  missing one renders as `null` and silently disabled the draft→ready transition.
- **`INTERVAL=0` was accepted and spun.** Intervals must now be at least 1s
  (offsets may still be 0). A zero interval made each nap return immediately,
  turning the watch into a busy loop around `gh` — measured at 200 naps in 2s,
  enough to exhaust the hourly REST budget in under a minute and leave the watch
  blind behind rate-limit failures for the rest of its window.

Two arguments that used to fail silently now behave: an empty `<last_head>` adopts
the first commit it observes instead of never detecting a push, and an empty
`<bot_slug>` is refused outright instead of leaving the watch waking on its own
posts.


## dnbg-workflow 2026.8.11 — 2026-08-09

The plugin now tells you when its enforcement gates are not actually running,
and the README states what the plugin needs to run at all.

**Why this matters.** The two blocking hooks parse their input with `jq` and
resolve repositories with `git`. If either is missing they don't block — they
fail *open*. Claude Code classes a hook exiting non-zero and non-2 as a
non-blocking error, so the edit proceeds, you get a `hook error` notice naming
the missing binary, and **Claude never sees that notice**, leaving the agent to
work as though the worktree and issue gates were live. On a machine without
`jq`, that state was permanent and effectively invisible.

Behavior change, effective as soon as the plugin updates:

- **`inject-rules.sh` now runs a dependency preflight at session start** and
  prints a warning naming the missing binary and what it disables — once per
  session, not once per intercepted tool call. `SessionStart` stdout is added to
  the session context, so the same message reaches you *and* Claude.
- **Missing `jq` and missing `git` are reported differently**, because they
  break different things: without `jq` neither gate can run, while without `git`
  `check-worktree` never fires but `check-issue-create` still gates a
  `--repo`-qualified command.
- **A missing `gh` is reported separately** from the two above — it stops the
  skills working rather than the gates, and one message covering both would
  misstate whichever half you acted on.
- **Nothing new blocks.** The gates keep failing open, and that is deliberate: a
  gate learns which repo an edit targets by parsing its payload, so with no
  parser it cannot tell a covered repo from any other. The only reachable "fail
  closed" would block every edit on the machine, including in projects you never
  listed in `owners`. The silence was the defect, not the fail-open.

The README gains a **Requirements** section listing all six binaries (`jq`,
`git`, `gh`, `python3`, `openssl`, `curl`) with what each is for and what
degrades without it, a documented Claude Code floor of **v2.1.207**, and an
honest platform statement: macOS and Linux are exercised, Windows/Git Bash is
untested and not claimed.


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

