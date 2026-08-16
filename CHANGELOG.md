# Changelog

What changed for someone using these plugins, newest first. Entries are
assembled at release time from the fragments in `changelog.d/`; see
`changelog.d/README.md` for how to write one.

Releases before this file existed are recorded in the git history; they were not
tagged, and their versions used a two-component scheme that predates the current
`YYYY.M.N`.

<!-- releases below -->

## dnbg-workflow 2026.8.61 — 2026-08-16

Reviews from the `reviewer` bot were not counting. GitHub does not let a review
from an App that lacks write access to repository contents affect a pull
request's approval state — so on a repo that requires an approval the bot could
never satisfy it, and threads it opened could not be resolved. The review
appeared on the PR, read correctly, and did nothing. It asks for that access
now, and `reviewer-setup` grants it when it creates an App.

Setting up a reviewer also checks what the App was actually granted, and says
what is missing and how to fix it if anything is. An App holding extra
permissions for other purposes is fine.

**This widens what a leaked reviewer key can do.** It could already read private
source on every repo the App is installed on; it can now write there too, and
merge. That is the cost of the bot's reviews counting, and GitHub offers no
narrower permission for it — so the repo list you install on is the only lever.
`SECURITY.md` covers it.

## Migration

**An App created before this release keeps its old permissions.** GitHub fixes
them when the App is created, so re-running the setup will not change one. Add
*Contents: Read and write* under your App's permissions, then accept the pending
request on each installation — the grant does nothing until you do.
`reviewer-setup`'s **Repair / rotate** section has the steps. If you skip this,
the reviewer will tell you the next time it runs.


## dnbg-workflow 2026.8.60 — 2026-08-16

Fixed a mergeable PR reporting as un-actionable on any repo with pre-receive
hooks — GitHub reports that state separately, and it was read as one nothing
recognises.

Merge state now distinguishes "mergeable", "ask again in a moment", and "GitHub
changed its API", where all three previously wore one answer. Only the last needs
a person.


## dnbg-workflow 2026.8.59 — 2026-08-16

Watching a PR is now a single wait from open through merge. The author's session
previously swapped between two watchers, and a reviewer who posted findings
*after* approving landed in the gap between them and was never reported.

Issues can now be watched for conversation — a comment, a body edit, a linked PR
appearing, or the issue closing — rather than only for a PR showing up. Several
issues ride one watch.

A check that stops passing now wakes the watch, instead of being noticed
whenever something else happened to.


## dnbg-workflow 2026.8.58 — 2026-08-15

Issues your agent files no longer argue for their own scope — why this is one
issue and not three, why it isn't a duplicate. Ordering constraints that
argument tended to carry are kept, attached to whatever they constrain.


## dnbg-workflow 2026.8.57 — 2026-08-15

A review run entirely through the GitHub API no longer loads its worktree-cleanup
instructions at the end, which cost context on every review to say there was
nothing to clean up.


## dnbg-workflow 2026.8.56 — 2026-08-15

The end-of-cycle report no longer pads its **Actionable** section. An item earns
a place there by naming a concrete next step and where; doubt now resolves toward
Observations. An empty section is a normal outcome of a clean cycle and simply
says so.

Applies to both reports — the reviewer's when the PR closes, and the author's
after a merge.


## dnbg-workflow 2026.8.55 — 2026-08-15

PR descriptions keep a measurement the argument rests on, bounding what it does
and does not establish, rather than cutting it to avoid an unearned claim.


## dnbg-workflow 2026.8.54 — 2026-08-15

PR descriptions claim less. A detail earns its place by changing what a reviewer
does, not merely by being true — a number that scopes the diff stays, a number
that only describes the work goes. Where a review finding's whole remedy is
editing prose that ships, the claim is cut rather than corrected, and `reviewer`
raises it that way.


## dnbg-workflow 2026.8.53 — 2026-08-15

Warning markers across the plugin are down to the ones that mark a genuinely
silent failure, so the remaining ones carry weight again.


## dnbg-practices 2026.8.6 — 2026-08-15

`coding-practices`' rule against counting a list you are introducing now covers
the case where the count scopes a *subset*. "These three carry a handoff" above a
list of seven is a count doing two jobs, and deleting the number leaves "these",
now claiming all seven — so name the members instead.


## dnbg-workflow 2026.8.52 — 2026-08-15

`git-workflow` is restructured along the path a change actually walks, and the
always-loaded part drops from about 10,000 words to 2,600. The review-round and
merge instructions load at the point each one binds, so a session that opens a
draft PR and stops there never pays for them.

Post-merge cleanup now travels with the merge rather than staying in the opening
flow, so a session told a PR merged reaches it cold.


## dnbg-workflow 2026.8.51 — 2026-08-14

A review round now arrives complete. The watch used to print comment bodies
without the threads or the diff, so it read as a finished round while carrying
most of one — a caller could act on it and be wrong, and a caller who fetched the
rest anyway paid for every body twice. It now hands over the exact command that
assembles the whole round, and `reviewer` runs it.


## dnbg-practices 2026.8.5 — 2026-08-14

`coding-practices` sharpens two rules about detail that costs more than it earns.

**Agent-facing prose gets a test for when rationale earns its line.** A
`SKILL.md`, rules file, or `CLAUDE.md` has two readers and charges one: the agent
loads every line on every run, the editor opens the file once. A *why* that
decides a case the instruction doesn't enumerate stays; a *why* that only defends
the instruction against a future editor belongs in the PR.

**A comment that counts the list it introduces** is now called out — the list
counts itself, and any added item silently falsifies the number.


## dnbg-workflow 2026.8.50 — 2026-08-14

`git-workflow` adds a step between committing and pushing: re-read your own diff
against the standards you loaded, with those files reopened rather than recalled,
and fix what you find before pushing.


## dnbg-workflow 2026.8.49 — 2026-08-14

Fixed a force-push carrying a standing approval onto the rewritten commit, so a
tree nobody had reviewed reported as approved. Both skills now check when the
approval was given against when the commit at HEAD was created.

Expect one extra review round after a rebase, including a rebase that only
inherits already-reviewed content. The reviewer re-verdicts unprompted on any
HEAD move, so the fresh approval arrives on its own.


## dnbg-workflow 2026.8.48 — 2026-08-14

Fixed two ways a reviewer silently lost events while watching a PR. Both looked
exactly like a quiet PR, which is what made them worth stating: re-arming a watch
with a freshly read clock opened a window nothing observed, and nothing said the
issue-scoped wait is a singleton, so a session could arm a second one alongside
the first.

Reviews cost fewer calls. Independent probes go in one call rather than a
sequence, a check needing the same field across many PRs or issues is one query
instead of a loop, and reading a repo's tree gains a middle gear between fetching
files one at a time and checking the whole thing out.

Between watch cycles a reviewer now reports a status line rather than restating
the review. The full report is owed once, when the PR closes.

None of this changes what a reviewer checks or concludes.


## dnbg-workflow 2026.8.47 — 2026-08-13

Reviews carry fewer non-blocking notes. Each minor observation an author acts on
moves HEAD, which correctly costs a fresh verdict, a fresh CI run, and often a
fresh round of notes about the fix — so an observation now has to earn its place
in the review body. Pacing is handed over as a sentence ("none of this needs a
round before merge") rather than a section headed "Non-blocking".

Nothing is removed from what a reviewer checks. The bar governs what gets
published, not what gets run.


## dnbg-workflow 2026.8.46 — 2026-08-13

`reviewer` is restructured along the review timeline, and the always-loaded part
drops from 860 to 633 lines — the watch, re-review and worktree instructions load
at the point each one binds.

**Loading the coding standards is now the review's first step**, ahead of reading
the diff, and the PR's repo decides which standards apply rather than your
working directory. A reviewer working remotely previously met nothing telling it
to load them at all.


## dnbg-workflow 2026.8.45 — 2026-08-13

Each review round is one call now, on both sides of the cycle: the round's diff,
the new activity, the standing verdict and every unresolved thread come back
together, where each side previously ran a sequence of reads that could be half
performed. The clean-review path also reads the approving review's body, so CI
triage or scope notes a reviewer left in an approval stop being re-derived from
scratch.


## dnbg-workflow 2026.8.44 — 2026-08-13

A review reaches you roughly half a minute sooner. The author's watch was waiting
out a coalescing window sized for an author's burst of separate actions; a
reviewer files its verdict and inline comments in a single write, so there was
nothing to coalesce.


## dnbg-workflow 2026.8.43 — 2026-08-13

Tightened the reviewer's verification discipline, so a review is less likely to
publish a finding that isn't real or approve something it never checked. Reviews
now read the PR at its head commit rather than a local branch, read whole files
when the question is whether something is *absent*, and run probes under the
target's real shell and working directory.

Mechanical gates — a formatter, a JSON parse, a required changelog fragment — are
left to CI, with the reviewer's judgment spent on whether what those gates
accepted is accurate.


## dnbg-workflow 2026.8.42 — 2026-08-13

Fixed every review posting under your personal GitHub account instead of the
reviewer bot. The token was minted in a tool call of its own, and an agent
harness starts a fresh shell per call, so it was gone before any command could
spend it — silently, since posting as yourself succeeds on a PR you did not
write. Each posting block now mints the token alongside the command that uses it,
and the review reports the identity it posted under.


## dnbg-workflow 2026.8.41 — 2026-08-12

Naming a draft PR for review now recommends **waiting** until it is marked ready,
and an unattended run takes that arm. Draft is the author's signal that the work
is not yet endorsed for review.

The finished cycle is reported under three headings — **Summary** (what
happened), **Observations** (nothing to do), **Actionable** (each naming a
concrete next step) — with "None" under an empty one. Neither skill acts on its
own Actionable list; filing and fixing stay your call.


## dnbg-workflow 2026.8.40 — 2026-08-12

The version stamp is now opt-in and **off by default**. It was landing an
invisible `<!-- dnbg-workflow <version> -->` comment on PR descriptions, review
bodies, and issue claim comments — artifacts published under your name, in repos
you may share with people who never installed this plugin.

Turn it on with the new `version_stamp` option in `/plugin` (Configure →
dnbg-workflow).

## Migration
Nothing to do unless you want the stamp. If you were relying on it to trace a
published PR or review back to the prompt version that produced it, enable
`version_stamp`, or the stamps silently stop appearing on everything published
after this update. Artifacts already stamped keep theirs.


## dnbg-practices 2026.8.4 — 2026-08-12

`coding-practices` now names failures specific to prose that instructs an agent —
a `SKILL.md`, an always-on rules file, a `CLAUDE.md`: an argument made twice, the
inverse of a condition the section is already scoped by, a read an earlier step
could have carried, and a branch the deployment never reaches.

The file also meets those rules itself now, and is shorter for it.


## dnbg-workflow 2026.8.39 — 2026-08-12

New always-on rule, **Coding standards stack**: load every standard that applies
before writing or reviewing code — the repo's own, yours, and
`dnbg-practices:coding-practices` when that plugin is installed — and hold the
work to all of them, with the project's own winning any disagreement. Authoring
prose that instructs an agent counts as writing code for this.

Nothing loaded `coding-practices` before, and `reviewer` never mentioned
standards at all, so a verdict was judged against whatever the model happened to
bring.

## Migration
This takes effect on an installed machine as soon as the plugin updates — it
applies to every session. If your repo has standards you did *not* want applied
to agent-facing prose (`SKILL.md`, `CLAUDE.md`), say so in the document itself;
the rule reads them as code.


## dnbg-workflow 2026.8.38 — 2026-08-12

Asking `reviewer` to review a draft PR now stops and asks — **"Review it now"**
(recommended) or **"Wait until it's ready"**, which reviews once the PR is marked
ready — instead of noting the draft status and reviewing anyway.

The question is skipped when you have already answered it in your request. An
unattended run, where nobody is there to answer, takes the wait arm; a headless
run that wants a verdict on a draft says so in its prompt. Drafts *discovered*
while reviewing an issue are unchanged: still held back without asking.


## dnbg-workflow 2026.8.37 — 2026-08-12

Stopped assuming your repo has branch protection. On a repo with no required
checks nothing is ever reported as blocked, and a fully red build reported as
merely unstable — which `git-workflow` handed over as a plain "ready to merge".

You still get the merge command immediately, including while checks are running,
but non-passing checks are named alongside it and a build that has already failed
is no longer framed as ready.


## dnbg-workflow 2026.8.36 — 2026-08-12

Fixed a review that landed while no watch was running being lost for good. Pushes
were already caught by comparing state, but a verdict posted during a gap in
watching was invisible and the watch reported idle — which reads as a PR nobody
has looked at.

A verdict at the current commit now wakes the watch however long it has been
sitting there. Both skills pass what is needed, so this applies without anything
on your side.


## dnbg-workflow 2026.8.35 — 2026-08-12

The workflow skills and the hooks' shared library shed the narration of the
defects that prompted their rules — history the skills were carrying into every
session. Every rule, guard reference and escalation is unchanged.


## dnbg-workflow 2026.8.34 — 2026-08-12

Reviews, PR descriptions, and issue claim comments now carry the plugin version
that produced them, as an HTML comment that renders invisibly. Sessions started
against a broken install omit the stamp rather than guessing.


## dnbg-workflow 2026.8.33 — 2026-08-12

Three `gh`/`jq` blocks that skill prose asked the agent to run verbatim are now
real scripts, covered by shellcheck and tests rather than by nothing.

Three behaviours the prose described but nothing enforced are now enforced: a
verdict reversed at the same commit is not an approval, PR discovery that loses a
source says so instead of reporting an empty set, and the reviewer bot is matched
by the login GitHub actually returns.


## dnbg-workflow 2026.8.32 — 2026-08-12

`reviewer-setup` states its installation-permissions check once instead of twice,
so there is no second copy to drift.


## dnbg-work-summary 2026.8.4 — 2026-08-12

`work-summary` drops Slack composer trivia that had dated itself, keeping the
part you can act on: emoji shortcodes must exist in the workspace, and
Cmd-Shift-V is the fix when formatting doesn't survive a paste.


## dnbg-workflow 2026.8.31 — 2026-08-12

`git-workflow` and the always-on rules shed prose recording how they got here
rather than instructing — the loops that preceded the shipped watchers, the
incidents behind two rules, a consent procedure `issue-workflow` already spells
out. Every rule is unchanged, and each session loads less.


## dnbg-workflow 2026.8.30 — 2026-08-12

`issue-workflow` splits filing an issue from resolving one, so each session loads
roughly half of what it used to: a filer drops the 2,600 words on claiming and
freshness probes, a resolver the 1,200 on writing a good body.


## dnbg-practices 2026.8.3 — 2026-08-12

Skill descriptions are shorter. A description loads into every session whether or
not its skill fires, and these had grown into summaries of their own contents.
They now carry identity, triggers, and skips only, and nothing about when a skill
loads has changed.


## dnbg-workflow 2026.8.29 — 2026-08-12

Skill descriptions are shorter. A description loads into every session whether or
not its skill fires, and these had grown into summaries of their own contents.
They now carry identity, triggers, and skips only, and nothing about when a skill
loads has changed.


## dnbg-work-summary 2026.8.3 — 2026-08-12

Skill descriptions are shorter. A description loads into every session whether or
not its skill fires, and these had grown into summaries of their own contents.
They now carry identity, triggers, and skips only, and nothing about when a skill
loads has changed.


## dnbg-workflow 2026.8.28 — 2026-08-12

`reviewer` sheds prose that recorded its own development rather than instructing.
Every rule it surrounded is unchanged, and each review loads less.


## dnbg-practices 2026.8.2 — 2026-08-12

`coding-practices` now applies its bar for what a comment must not carry to prose
that instructs an agent — skill files, always-on rules, `CLAUDE.md` — and loads
when you are authoring that prose. Its trigger previously skipped "non-code
questions", so it never reached the sessions where skill prose gets written.


## dnbg-workflow 2026.8.27 — 2026-08-12

`reviewer`'s issue-scoped mode moves to a reference file, so a PR-scoped review no
longer loads the 2,100 words it never uses.


## dnbg-workflow 2026.8.26 — 2026-08-12

`reviewer` no longer files style nits as inline comments. An inline comment is a
review thread, and a thread blocks the merge outright wherever a repo requires
conversations resolved — so a nit filed on a line held the merge hostage while the
review body called it non-blocking.

Inline-vs-body is now decided on "would you hold the merge for it", filing a
thread goes with requesting changes so the verdict and the threads agree, and a
nit-thread that turns out to be the last blocker gets resolved.


## dnbg-workflow 2026.8.25 — 2026-08-11

The worktree hook's block message now names the file and the retry path correctly
when the repo is reached through a symlink — on macOS, anything under `/tmp`, and
any symlinked home or project directory. The path it told you to retry with was
previously a location that could not exist.

The gate itself is unchanged. Only the text you act on after a block was wrong.


## dnbg-workflow 2026.8.24 — 2026-08-11

`reviewer-setup` points at current documentation for the reviewer key's sources,
rather than a README section that no longer exists. The skill relays that pointer
to you when it sets the bot up, so the stale one was reaching users.


## dnbg-workflow 2026.8.23 — 2026-08-10

New always-on rule: when a script, hook, or procedure the plugin ships doesn't
cover your case, the agent finishes the task the narrow way, then tells you what
didn't fit and offers to report it upstream.

Filing is never agent-initiated. An issue against this project is published under
*your* GitHub identity to a repo you don't control, so it happens only if you ask
for it, is written from the generic case with nothing session-specific in it, and
is shown to you in full for approval before it is submitted. With no user present
to ask, nothing is filed.

The rule also states two things that were previously implicit: a hook that blocks
you is working as intended and should be satisfied rather than routed around, and
the installed plugin copy under `~/.claude/plugins/` is never a place to edit —
those edits are unreviewed and are destroyed by the next update.


## dnbg-workflow 2026.8.22 — 2026-08-10

The always-on rules now reach subagents, not just the main conversation. Any
subagent you spawned had never been told to work in a worktree, to reference
issues by full URL, or about any configuration override you had set.

This is a behavior change on an installed machine: subagents now see the rules
and act on them, and each spawn costs the tokens the rules occupy.


## dnbg-workflow 2026.8.21 — 2026-08-10

The workflow skills now state that they are GitHub-only and decline cleanly on
another forge, instead of running `gh` commands that cannot work and surfacing a
cascade of confusing errors.

What decides is the repo holding the work, not your working directory — so
picking up a GitHub issue from a GitLab checkout, or reviewing a GitHub PR from
one, works normally. A repo with no `origin` is not treated as a decline: it makes
no forge claim either way.

The README gains a support matrix naming every forge, and says which plugin ships
each skill and whether that skill needs a forge at all.


## dnbg-work-summary 2026.8.2 — 2026-08-10

`work-summary` now states that it recaps GitHub work specifically, and that it is
scoped to your GitHub account rather than to any repository.

The practical effect is a guarantee rather than a restriction: asking for a recap
of your GitHub week while sitting in a GitLab checkout — or in no repo at all — is
a supported request.


## dnbg-workflow 2026.8.20 — 2026-08-10

The issue-scoped wait now wakes on PRs that reference an issue without a closing
keyword, and the claim check sees them too. Both previously asked GitHub only for
PRs carrying a closing keyword.

A real resolving PR that linked the issue in prose therefore never woke the
watch: it ran its full window, reported idle, and then presented the issue number
as probably wrong — while the unreviewed PR could merge. The same gap made an
in-flight multi-repo change read as unclaimed the moment its closing PR merged,
so a second session could start work that was already half shipped.

A timeline source going blind is now reported rather than presenting as a quiet
issue.


## dnbg-workflow 2026.8.19 — 2026-08-10

Two of the workflow's mechanical choices are configurable from `/plugin`,
alongside `owners`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `worktree_path` | `.worktrees` | Repo-relative directory worktrees are created in |
| `claim_label` | `assigned:agent-session` | Label an agent session applies when it claims an issue |

Set one and a note at session start says so, which the skills read as overriding
their defaults. Set neither and nothing changes. A rejected value falls back to
the default with the reason printed at session start rather than being silently
ignored — a worktree path has to stay inside the repo, and a claim label has to
start with `assigned:`, since that whole namespace is what the check for someone
else's claim matches.

What stays fixed, deliberately: PRs always open as drafts, the send-to-review
question and its option order, the sibling-PR title tag, and "only a human
merges".


## dnbg-workflow 2026.8.18 — 2026-08-09

`git-workflow` described the PR watcher's argument handling wrongly in three
places. All three are corrected; no behaviour changed.


## dnbg-workflow 2026.8.17 — 2026-08-09

The PR watcher no longer reports a push that never happened. An abbreviated
commit SHA could never match the full one GitHub returns, so a watch armed with a
short one reported a push within seconds of starting, with nothing pushed —
`reviewer` read that as a delta to re-review and `git-workflow` read it as the
author pushing, and neither could tell it from the real thing.

A short SHA is now refused outright. Both skills already passed the full one.


## dnbg-workflow 2026.8.16 — 2026-08-09

Issue claims use the label `assigned:agent-session` instead of
`assigned:claude-code`, and the claim comment names the claiming session.

Naming the session turns a question that was previously undecidable — is this
claim my own earlier mark, or a sibling session's? — into a comparison. Only an
exact match licenses proceeding, so any claim that can't be positively accounted
for still stops and asks. The practical gain is unattended runs, which previously
had to stop on *every* claim from your own account, including their own.

**Claims already on your issues keep working and need no cleanup.** The pickup
check matches the whole `assigned:*` namespace, so an issue carrying the old
label is still detected as claimed. There is no relabeling script and none is
needed.


## dnbg-workflow 2026.8.15 — 2026-08-09

The reviewer bot's private key can now come from a secret manager or the
environment instead of a plaintext file, and its directory is hardened.

The key is resolved from the first source that yields one:

1. `DNBG_REVIEWER_PRIVATE_KEY` — the PEM itself.
2. `DNBG_REVIEWER_PRIVATE_KEY_COMMAND`, or `private_key_command` in
   `config.json` — a command whose stdout is the PEM (`op read`, `pass show`,
   `security find-generic-password -w`, `secret-tool lookup`, `vault kv get`,
   `sops -d`).
3. `~/.config/dnbg/reviewer/private-key.pem` — the existing default, unchanged.

Route 1 paired with `DNBG_REVIEWER_APP_ID` needs no config file or PEM on disk at
all, which makes running the reviewer in CI possible for the first time. A key
from route 1 or 2 is never written to disk — it goes through a pipe rather than a
temp file, so a crash cannot strand it.

The key command is read only from your user config or the environment, never from
a repository. Nothing reads config from the working directory.

## Migration
Minting now refuses to run against a group- or world-writable config directory or
key file, the way `ssh` refuses an over-permissive private key. If yours is loose
it will stop and tell you; fix with `chmod go-w ~/.config/dnbg/reviewer`, or
re-run the setup, which now tightens the directory to `0700` over an existing
one.


## dnbg-workflow 2026.8.14 — 2026-08-09

`git-workflow` now handles a watcher that returns nothing. Both of its watch
loops treated a killed watcher as indistinguishable from a quiet one — which
matters most on the merge watch, which runs for hours while you are away, where a
kill could swallow the merge and skip the post-merge cleanup entirely. Both now
re-read the PR's real state rather than trusting the watcher's silence.

A watcher's trace also records its own arguments, so a stray trace says which PR
it was watching rather than only that a watch died.


## dnbg-workflow 2026.8.13 — 2026-08-09

**The issue-creation gate no longer blocks commands that merely talk about
creating an issue.** It matched the phrase anywhere in a command string —
including inside a quoted argument or a heredoc body, where it is text rather
than a command — so any command whose payload discussed issue creation was
blocked. Review bodies, commit messages and issue text are exactly the payloads
most likely to do that.

The gate now requires the phrase to be in command position. Genuine invocations
are unaffected, including ones that follow another command.


## dnbg-workflow 2026.8.12 — 2026-08-09

The PR and merge watchers can now explain their own death, and three ways a watch
could go silently blind are fixed.

**Tracing, on by default.** Both watchers record a line per poll, per signal, and
at exit, under `${TMPDIR:-/tmp}/dnbg-watch/`, swept after three days.
`WATCH_LOG=<path>` redirects it and `WATCH_LOG=off` turns it off, after which
nothing is installed and nothing is spent. A killed watch otherwise leaves no
evidence anywhere: its one result line is written at exit, so it produces an
empty output file, and macOS records ordinary process signals nowhere.

Fixed, each of which previously left a watch running and reporting something
plausible but wrong:

- **Replies behind a page of older comments were invisible.** On a PR with more
  than 30 inline comments, every new reply sat on a page the watch never fetched.
  It saw only history, never woke, and idled out looking healthy — most likely to
  bite on a busy PR with several reviewers.
- **An API error body passed the shape gate.** It is well-formed JSON, so it was
  accepted with an empty state, and the watch ran its whole window against it and
  reported idle on a PR that had already closed.
- **A zero poll interval was accepted and spun**, turning the watch into a busy
  loop that could exhaust the hourly API budget in under a minute and leave it
  blind behind rate-limit failures for the rest of its window.

Also on the shipped path, whether or not you enable tracing: a watch now takes a
termination signal while napping instead of deferring it for up to a full poll
interval.


## dnbg-workflow 2026.8.11 — 2026-08-09

The plugin now tells you when its enforcement gates are not actually running.

Both blocking hooks parse their input with `jq` and resolve repositories with
`git`. If either is missing they fail *open* — the edit proceeds, you get a `hook
error` notice naming the missing binary, and **Claude never sees that notice**,
so the agent works as though the worktree and issue gates were live. On a machine
without `jq`, that state was permanent and effectively invisible.

A dependency preflight now runs at session start and prints a warning naming the
missing binary and what it disables — once per session, and to you *and* Claude.
Missing `jq`, `git` and `gh` are reported separately, because they break
different things.

**Nothing new blocks.** The gates keep failing open, deliberately: a gate learns
which repo an edit targets by parsing its payload, so with no parser it cannot
tell a covered repo from any other, and the only reachable "fail closed" would
block every edit on the machine. The silence was the defect, not the fail-open.

The README gains a **Requirements** section listing the binaries the plugin needs
and what degrades without each, a documented Claude Code floor of **v2.1.207**,
and an honest platform statement: macOS and Linux are exercised, Windows/Git Bash
is untested and not claimed.


## dnbg-workflow 2026.8.10 — 2026-08-08

Both background watchers now measure time in **laptop-open seconds** and share
one poll curve.

- **A suspended machine no longer burns a watch.** Closing the lid overnight used
  to retire the merge watcher's whole window, so it woke to an already-blown
  deadline and reported "watched the full window, no merge" having never once
  looked. Suspended time is now discounted from both the window and the poll
  interval, and a watch comes back at its 10-second floor — fastest at exactly the
  moment you have reopened the machine.
- **New poll curve, shared by every watch:** 10s at the start, easing to 30s over
  half an hour, a minute by the 90-minute mark, then 5 minutes flat. Whatever you
  are waiting for usually happens in the first few minutes and nearly always
  within the hour, so the wait is short when it matters and cheap when it
  doesn't. Tunable via `POLL_CURVE`.
- **A short outage no longer ends a watch.** Declaring the watch broken now needs
  both a run of failed ticks and a few minutes of awake time.
  Lid-open-then-reconnect was previously the likeliest way to lose a watch on a
  healthy PR.


## dnbg-workflow 2026.8.9 — 2026-08-08

**The reviewer no longer re-runs the project's test suite.** A local run
reproduces the author's environment rather than CI's, so on a timing- or
load-sensitive defect it argues "flaky, ignore it" — the wrong verdict. It reads
the check results instead, and never waits for or polls CI. Reproducing one
doubted claim under instrumentation is still permitted, triggered by doubt about
a specific claim rather than by a red check.

It also reads less of each file, and a re-review reads only the changes the prior
verdict did not cover.

Judging test coverage by *reading* tests is unchanged; the restriction is
narrowly about executing them.


## dnbg-workflow 2026.8.8 — 2026-08-08

The reviewer now re-posts its verdict whenever new commits land past the commit
its standing approval is attached to, even when the verdict is unchanged. It
previously stayed silent on a change it judged trivial, which left the approval
pointing at an older commit while GitHub's merge box showed an unqualified green
check — and left the author's watch waiting for a signal the reviewer had been
told not to send.

Both skills now answer "is HEAD approved?" by checking the latest verdict
directly, rather than inferring it from the repo's *Dismiss stale pull request
approvals* setting. That setting is meaningless where no approval is required —
the default on a personal repo that gates on CI — so the inference produced
confidently wrong answers in both directions. Nothing reads branch protection any
more, which is one less call that needs admin.


## dnbg-workflow 2026.8.7 — 2026-08-08

The PR/issue watcher no longer reports a broken watch as a quiet one. If a poll
source fails repeatedly it says so, and both skills stop and tell you to check
`gh auth status` rather than re-arming into the same failure forever. Previously
a watch that never once reached GitHub ran out its window and printed the same
idle result a genuinely calm PR prints.

A quieter version of the same bug is fixed too: a failed thread-replies query
read as "no new replies" while the main poll kept succeeding, so the watch looked
healthy and was partly blind.

Polling is a curve rather than a fixed 30s. It starts at 10s so a reply lands
almost immediately, holds 30s for an hour after the last activity, then backs off
to 15 minutes. A 6-hour watch costs roughly a fifth of the API calls it used to,
while the first minute gets faster.


## dnbg-workflow 2026.8.6 — 2026-08-08

The reviewer bot's credentials move from `~/.config/agent-reviewer/` to
`~/.config/dnbg/reviewer/`, so everything this marketplace writes to disk now
lives under one `dnbg` directory. The override environment variable is renamed
`REVIEWER_CONFIG_DIR` → `DNBG_REVIEWER_CONFIG_DIR`.

The GitHub App itself is **not** renamed. It stays `agent-reviewer-<your-login>`,
because it is your identity on other people's pull requests rather than something
this marketplace owns.

## Migration
If you have already set up the reviewer bot, move its directory:

    mkdir -p ~/.config/dnbg && mv ~/.config/agent-reviewer ~/.config/dnbg/reviewer

Nothing reads the old location any more, and there is no compatibility fallback.
An unmigrated install fails with `reviewer bot is not set up (no credentials in
<dir>)` naming the directory it searched, so it says exactly what is wrong rather
than failing silently.

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
radius, reversibility, time-to-notice, test coverage, users — and not a fact about
the project.

## Migration
**Any repo whose `CLAUDE.md` opts in must change
`dnbg-workflow:prototype-velocity` to `dnbg-workflow:velocity-tradeoff`.** The old
name does not error; it silently stops loading, so the opt-in simply stops taking
effect.

If you want `coding-practices` or `work-summary`, install them:

    /plugin install dnbg-practices@dnbg
    /plugin install dnbg-work-summary@dnbg

or `/plugin install dnbg-all@dnbg` for everything. This plugin does **not**
depend on them.


## dnbg-work-summary 2026.8.1 — 2026-08-07

First release. `work-summary` now ships as its own plugin. It has no dependencies
on the other skills and installs no hooks.


## dnbg-all 2026.8.1 — 2026-08-07

First release. Installs `dnbg-practices`, `dnbg-workflow` and `dnbg-work-summary`
— everything in this marketplace, in one command.

Its dependencies are unversioned, so it tracks whatever version of each sibling
the marketplace provides rather than pinning them.


## dnbg-workflow 2026.8.4 — 2026-08-07

Only `github.com` remotes are covered by the enforcement hooks now. The owner
match previously ignored the remote's host, so listing a GitHub org also gated a
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

The plugin no longer updates itself. Its self-update hook is removed, so it now
makes no network access at all, and what you install is what runs until you
update it.

Claude Code's own per-marketplace auto-update does the same job and does it
sooner: it checks after each session starts rather than throttling to once every
four hours.

## Migration
Nothing breaks, but **you will stop receiving updates automatically** unless you
turn them on. In `/plugin` → Marketplaces → dnbg → Enable auto-update. The removed
hook also left a throttle stamp behind; delete it if you like:

    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/dnbg-workflow/last-update"


## dnbg-workflow 2026.8.2 — 2026-08-07

The PR watcher used by `git-workflow` is now the same hardened script `reviewer`
uses. The author side previously inlined its own loop, which polled for a review
on the current commit — right after pushing a fix, wrong after replying in
threads, where nothing moves and the watcher matched the review it had already
handled.

`git-workflow` also gains runnable commands for enumerating unresolved review
threads and for replying in a thread and resolving it, replacing prose that was
easy to skip.


## dnbg-workflow 2026.8.1 — 2026-08-07

Plugin versions move to `YYYY.M.N` — year, unpadded month, Nth release of that
plugin that month. Each plugin carries its own counter, and releases are driven by
changelog fragments rather than firing on every merge. Releases are now tagged
(`{plugin}--v{version}`) and published as GitHub Releases.

Nothing is required of you. The previous two-component scheme (`2026.4`) was not
semver-parseable, so no tag it produced could be selected by plugin dependency
resolution; anyone scripting against it should expect three components from now
on.
