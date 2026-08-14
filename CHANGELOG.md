# Changelog

Entries are assembled at release time from the fragments in `changelog.d/`.
Newest first. See `changelog.d/README.md` for how to add one.

Releases before this file existed are recorded in the git history; they were not
tagged, and their versions used a two-component scheme that predates the current
`YYYY.M.N`.

<!-- releases below -->

## dnbg-workflow 2026.8.49 — 2026-08-14

A force-push can move a standing review onto the rewritten commit, so the
"is HEAD approved?" check reported an approval for a tree nobody had reviewed.
`pr-verdict.sh` and `pr-round.sh` now also report `reviewed_after_head`, from
the verdict's submission time against when the commit at HEAD was created, and
both `git-workflow` and `reviewer` require it alongside `at_head`.

Expect one extra review round after a rebase, including a rebase that only
inherits already-reviewed content. The reviewer re-verdicts unprompted on any
HEAD move, so the fresh verdict arrives on its own.


## dnbg-workflow 2026.8.48 — 2026-08-14

Closed two ways `reviewer` silently lost events when re-arming a watch. Both
looked exactly like a quiet PR, which is what made them worth stating.

**Re-arming with a self-generated timestamp opened a blind window.**
`references/watch.md` said to carry the `now` the watcher reported but never said
why, so a fresh `date -u` read as an equivalent source of it — and the interval
between the two readings is observed by no watch. The step now carries the reason
and names what survives a gap: commits and verdicts do, being level-triggered by
head SHA and `--last-verdict`; comments, replies and `COMMENTED` reviews are
counted against `since_iso` and are dropped for good. `SKILL.md`'s record-state
step, which previously named `date -u` unqualified, now scopes it to the first
arm.

**Nothing said the issue-scoped wait is a singleton.** `references/issue-mode.md`
told the reviewer to re-discover on every watcher return, which could be read as
arming a *second* issue wait alongside the one already running — each paginating
the whole timeline every tick, both reporting the same `CLOSED`. It now states
that at most one exists at a time, re-armed only on its own return, and that an
armed issue wait *is* the discovery mechanism, so a PR watcher's return need only
handle its own PR. Discovery stays unconditional with no issue wait armed, at any
`CLOSED`, and on the issue wait's own `ACTIVITY`.

`reviewer` now spends fewer calls per review. It previously budgeted only bytes,
so a reviewer could read economically and still burn a cycle on round trips: the
round trip is now named as a cost alongside bytes, independent probes go in one
call rather than a sequence, and a check needing the same field across many PRs
or issues is one GraphQL query instead of a `gh` loop per item. The per-call bot
token mint is explicitly exempted — it is an extra API call, not an extra round
trip, and collapsing those blocks posts the review under the wrong identity.

Reading the tree gained a middle mode, as a new `scripts/fetch-tree.sh`. Between
per-file `contents` fetches and a full worktree, one call now pulls the whole
tree at a SHA into a scratch directory and leaves nothing in the repo to clean
up — worth it past ~2 questions of the tree, or for any repo-wide sweep. It is a
script rather than a snippet because the failure is silent in the worst
direction: a fetch that goes wrong leaves an *empty* tree, and a sweep over one
comes back with zero hits — exactly the answer an absence check is looking for.
It reports `reason=fetch` or `reason=empty` instead, so an empty tree can never
be mistaken for a clean sweep. The worktree triggers narrowed to match — a
probe that *runs* something still needs a checkout, a probe that only reads gets
its files fetched.

Three smaller additions: whole-file fetches are filtered at the pipe rather than
landing in context; `gh pr diff`'s lack of pathspec support is stated with the
per-file-patch idiom that replaces it; and the round packet is named as the
source for incoming comments, rather than the reviewer fanning out across
comment endpoints that can only re-fetch what it already has.

Between watch cycles, a reviewer now reports a status line rather than restating
the review. The review body is the artifact, and the full three-section report is
owed once, when the PR closes.

None of this changes what a reviewer checks or concludes.


## dnbg-workflow 2026.8.47 — 2026-08-13

`reviewer` now applies a bar to non-blocking observations before they go in a
review body. Previously the only test was "does this block the merge", so a
correct-but-minor note went in unchallenged — and each one an author acted on
moved HEAD, which correctly costs a fresh verdict, a fresh CI run, and often a
fresh round of notes about the fix. Five tests now gate the body: could acting on
it change a tracked file; did this diff change the line or make it wrong; does
your own phrasing ("defensible", "reasonable either way") already argue it down;
could you be wrong in a way only the author can check, from session state a
reviewer never sees; and, on a re-review, would it have been worth raising in
round 1. Reviews now hand the pacing decision over as a sentence — "none of this
needs a round before merge" — rather than a section headed "Non-blocking".

None of this reduces what a reviewer checks. Every test bars a *finding from
being published*; none bars a *check from being run*.

Two rules moved to where they bind. The ban on padding a review with CI status
now sits with the body-composition instructions rather than in the CI step, and
says that a check result changing the verdict is a finding while one that does
not belongs only on the PR page, where it is live rather than a stale snapshot.
The anti-filler rule now covers re-verdict bodies as well as thread replies: a
re-verdict states the SHA, the verdict, and what changed, without ratifying the
author's reasoning back at them. Verification is reported selectively — narrated
on `APPROVE` where it justifies the verdict, compressed to a list of surfaces
checked on `REQUEST_CHANGES`.


## dnbg-workflow 2026.8.46 — 2026-08-13

Split `reviewer`'s `SKILL.md` along the review timeline rather than by topic. The
file now carries the path a first pass actually walks — identify the PR, get a
token, do the work, post, spawn the watch — and hands off to three new reference
files at the point each one binds: `references/watch.md` on the watcher's first
return, `references/re-review.md` when HEAD moves, and `references/worktree.md`
on the minority of reviews that need a checkout. Each is pointed at from the step
that precedes needing it, so nothing has to be found from a reference list. The
skill drops from 860 to 633 lines.

The motivation is placement as much as size: several rules were correct but sat
in a section the reviewer was not in when they applied.

**Loading the coding standards is now step 1 of the review**, ahead of reading
the diff, and it says whose standards apply — the PR's repo decides, not your
working directory, which for a reviewer working remotely is not the same thing.
Previously the flow began at "read the diff" and only mentioned the standards in
passing four steps later, phrased as though they were already loaded; a reviewer
that had not loaded them met nothing that said to. In the issue-scoped mode the
load belongs in the wait for PRs to appear, which is where `references/issue-mode.md`
now puts it.


## dnbg-workflow 2026.8.45 — 2026-08-13

Consolidated each review round into one call, on both sides of the cycle. A new
`scripts/pr-round.sh` returns the round's delta diff, the new activity (review
bodies, conversation comments and inline findings alike), the standing verdict,
and every unresolved thread in a single invocation — where `git-workflow` and
`reviewer` each previously ran a sequence of separate reads that could be
partially performed. `git-workflow`'s clean-review path now also reads the
approving review's body before composing the merge handoff, so CI triage or
scope notes a reviewer left in an approval stop being re-derived from scratch.

`watch-pr.sh` no longer discards what it polled: the comments and replies behind
`activity=1` are printed as JSON above its result line, so acting on them costs
no second fetch, and the standing verdict's state is reported as `verdict=`
alongside `verdict_sha=` as a hint for branching before that fetch. Every source
in the packet reports its own status, so an empty section that failed to load is
distinguishable from one that is genuinely empty.


## dnbg-workflow 2026.8.44 — 2026-08-13

`git-workflow`'s review watch now settles for 10s instead of the script's 45s
default, so a review reaches you roughly half a minute sooner. The default is
sized to coalesce an author's burst of separate actions, which is what `reviewer`
watches; a reviewer files its verdict and inline comments in a single write, so
the author side was paying a coalescing window it had nothing to coalesce.


## dnbg-workflow 2026.8.43 — 2026-08-13

Tightened the `reviewer` skill's verification discipline, so a review is less
likely to publish a finding that isn't real or approve something it never
checked. Reviews now read PR content at the head SHA rather than a local branch
ref, derive a local changed set against the merge-base, read whole files when the
criterion is that something is *absent*, run probes under the target's real shell
and working directory, and re-list before retrying a review POST that 5xx'd.
Mechanical gates (a required changelog fragment, a JSON parse, a formatter) are
left to CI, and a generated artifact (a GIF, a snapshot, a lockfile) is
render-verified once rather than every round — with the reviewer's judgment spent
on whether what those gates accepted is accurate. Two techniques added: sweeping
a feature's identifier families before reading the diff, and computing countable
properties instead of eyeballing them.


## dnbg-workflow 2026.8.42 — 2026-08-13

Fixed the `reviewer` skill minting its bot token in a tool call of its own. An
agent harness starts a fresh shell per call, so the token was gone before any
`gh` command spent it and every review posted under the operator's personal
account instead of `agent-reviewer-<owner>[bot]` — silently, since that call
succeeds on a PR the operator did not write. Each posting block now mints the
token alongside the command that uses it, and the review POST prints the
identity it posted under.


## dnbg-workflow 2026.8.41 — 2026-08-12

Two changes to what the skills do around the end of a review cycle.

`reviewer`'s draft picker now recommends **waiting**. Naming a draft PR for
review still asks before reviewing it, but the options are reversed: "Wait until
it's ready" is the recommended first option and the one an unattended run takes,
and "Review it now" is second. Draft is the author's signal that the work is not
yet endorsed for review, which is already why a draft the reviewer *discovers*
is held back without asking at all.

`git-workflow` and `reviewer` now report the finished cycle under three
headings — **Summary** (what happened), **Observations** (informational, nothing
to do), **Actionable** (things the operator may want to act on, each naming a
concrete next step). All three appear every time, with "None" under an empty
one, and an item that could go under either lands in Actionable. Neither skill
acts on its own Actionable list: filing and fixing stay the operator's call.


## dnbg-workflow 2026.8.40 — 2026-08-12

The version stamp is now opt-in and **off by default**. When it was introduced,
every session stamped an invisible `<!-- dnbg-workflow <version> -->` comment
onto PR descriptions, review bodies, and issue claim comments. That text lands on
artifacts published under your name in repos you may share with people who never
installed this plugin, so it is now something you switch on rather than something
you inherit.

Turn it on with the new `version_stamp` option in `/plugin` (Configure →
dnbg-workflow). With it off, the session-start note that carries the version is
not emitted at all and the three publishing skills leave the stamp out.

## Migration

Nothing to do unless you want the stamp. If you were relying on it — to trace a
published PR or review back to the prompt version that produced it — enable
`version_stamp` from `/plugin`, or the stamps silently stop appearing on
everything published after this update. Artifacts already stamped keep theirs.


## dnbg-practices 2026.8.4 — 2026-08-12

`coding-practices` now names four failures specific to prose that instructs an
agent — a `SKILL.md`, an always-on rules file, a `CLAUDE.md`. It already held
that prose to the comment bar; the failures it listed under that bar were all
comment-shaped. The new ones are an argument made twice, the inverse of a
condition the section is already scoped by, a read an earlier step could have
carried, and a branch the deployment never reaches.

The file also now meets those rules itself:

- Its guidance stands on its own rather than on claims about what the Claude
  Code system prompt says — five of those are gone, including the framing of
  "Two abstraction vices", which read as a corrective to a caution attributed to
  a document that changes between model releases.
- "Don't write API code from memory" is stated once, with pointers, instead of
  three times over three sections.
- No warning marker: the only one sat on a Markdown-editing hazard, which is
  none of the categories its own rule reserves the glyph for. The rule under it
  survives as one sentence.


## dnbg-workflow 2026.8.39 — 2026-08-12

Standards now reach the author and the reviewer without either having to think
to go looking. A new always-on rule, **Coding standards stack**, says to load
every standard that applies before writing or reviewing code — the repo's (its
`CLAUDE.md`, any standards doc it names), yours, and
`dnbg-practices:coding-practices` when that plugin is installed — and to hold the
work to all of them, with the project's own winning any disagreement. Authoring
prose that instructs an agent counts as writing code for this.

Nothing loaded `coding-practices` before: it ships no hook, and `git-workflow`
and `issue-workflow` mentioned it only as an optional install. `reviewer` never
mentioned standards at all, so a verdict was judged against whatever the model
brought. Its "Review for" step now names them.

## Migration
This takes effect on an installed machine as soon as the plugin updates —
`always-on-rules.md` applies to every session. If your repo has standards you did
*not* want applied to agent-facing prose (`SKILL.md`, `CLAUDE.md`), say so in the
document itself; the rule reads them as code.


## dnbg-workflow 2026.8.38 — 2026-08-12

Asking `reviewer` to review a draft PR now stops and asks, instead of noting the
draft status and reviewing anyway. It offers **"Review it now"** (recommended —
the old behavior) or **"Wait until it's ready"**, which arms the existing
`--was-draft` watch and reviews once the PR is marked ready.

The picker is skipped when you have already answered — "review it even though
it's a draft", "review it once it's ready". **In an unattended run** — a CI or
headless reviewer, the case `DNBG_REVIEWER_PRIVATE_KEY` exists for — nobody is
there to answer, so it takes the wait arm and reviews when the PR is marked
ready. A headless run that wants a verdict on a draft pre-answers the picker in
its prompt. Drafts *discovered* in issue mode are
unchanged: still held back without asking.


## dnbg-workflow 2026.8.37 — 2026-08-12

Stopped assuming your repo has branch protection. Two rules were justified by a
merge gate the plugin cannot read and many repos do not have — on a repo with no
required checks, nothing is ever `BLOCKED` and a fully red build reports as
`UNSTABLE`, which `git-workflow` handed over as a plain "ready to merge".

- `git-workflow` now gives `UNSTABLE` its own arm in "Composing the merge
  command". You still get the merge command immediately, including while checks
  are running — non-passing checks are named alongside it, and a build that has
  already failed is no longer framed as ready to merge.
- `reviewer` keeps both of its CI rules (never hold a verdict for CI, never poll
  it) on reasoning that holds on any repo, instead of on branch protection
  catching red CI later.
- The posture behind both is stated once, in `reviewer`'s new "Repo settings you
  cannot read": an unreadable setting is assumed in whichever direction is safe,
  and no instruction rests on one being on.


## dnbg-workflow 2026.8.36 — 2026-08-12

`watch-pr.sh` no longer loses a review that landed before the watch was armed.
Pushes were already detected by comparing state, so one that happened while no
watcher was running was still caught; reviews were counted against `since`, so a
verdict posted during a gap in watching — or before the `since` a re-arm was
given — was invisible for good, and the watch reported `IDLE`, which reads as a
PR nobody has looked at.

The new `--last-verdict=<sha>` argument carries the SHA the caller last handled a
verdict for. Each poll compares the standing verdict against it, ignoring
`since`, so a verdict at the current HEAD wakes the watch however long it has
been sitting there. The watch's own verdicts never wake it, under either spelling
of a bot login. When the check fires, the result line carries `verdict_sha=<sha>`
to re-arm with.

`git-workflow` and `reviewer` both pass it now, so the fix applies without
anything on your side. Omitting the argument leaves the previous behaviour
exactly as it was.

Trailing arguments are now accepted in any order and refused when unrecognised —
`--was-draft` was previously read only in position six, and a second flag would
have silenced one of them depending on typing order.


## dnbg-workflow 2026.8.35 — 2026-08-12

Trimmed the incident history out of `git-workflow`, `reviewer`, `issue-workflow`
and the hooks' shared `lib.sh`. Every rule, guard reference and escalation is
unchanged — what went is the narration of the defects that prompted them, which
`coding-practices` bans in prose that instructs an agent.


## dnbg-workflow 2026.8.34 — 2026-08-12

Reviews, PR descriptions, and issue claim comments now carry the plugin version
that produced them, as an HTML comment that renders invisibly. Sessions started
against a broken install, or without `jq`, omit the stamp rather than guessing.


## dnbg-workflow 2026.8.33 — 2026-08-12

Three `gh`/`jq`/GraphQL blocks that skill prose asked you to run verbatim are now
scripts under `scripts/`, so they are covered by `shellcheck` and by tests rather
than by nothing: `pr-verdict.sh` (is the standing verdict attached to HEAD?),
`pr-sources.sh` (every PR that might resolve an issue), and `pr-threads.sh` (list
or resolve review threads).

Three behaviours the prose copies described but nothing checked are now enforced:
a verdict reversed at the same SHA is not an approval, discovery that loses a
source says so instead of reporting an empty set, and `--mine` matches the
reviewer bot the way GraphQL actually spells its login.


## dnbg-workflow 2026.8.32 — 2026-08-12

`reviewer-setup` states its installation-permissions check once instead of twice —
the copy under "Repair / rotate" now points at the one under "Verify", so there is
no second copy to drift.


## dnbg-work-summary 2026.8.4 — 2026-08-12

`work-summary` drops Slack composer trivia that dated itself — which composer
reads single asterisks as bold, and an instruction to re-check it — keeping the
part a user can act on: emoji shortcodes must exist in the workspace, and
Cmd-Shift-V is the fix when formatting doesn't survive a paste.


## dnbg-workflow 2026.8.31 — 2026-08-12

`git-workflow` and the always-on rules shed prose that recorded how they got
here rather than instructing: the loops that preceded the shipped watchers, the
incidents that motivated two rules, and a consent procedure `issue-workflow`
already spells out. Every rule is unchanged, including the ones the cut passages
surrounded.


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

