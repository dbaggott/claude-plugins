# Give each agent role its own forge identity

As-built design of https://github.com/dbaggott/claude-plugins/issues/423.

Section IDs (`C#`, `R#`, `D#`, `Q#`, `A#`) are the ones the children, PRs and commits cite, unchanged from the tracking issue. Problem and Constraints describe the plugins as they stood before this work, and "today" in them means then.

Each agent role (reviewer, author, orchestrator) acts on the forge under its own identity, so the operator's account means "a human did this" again. GitHub Apps are how it is built, and the seam is drawn so GitLab and Bitbucket backends can supply the same identities later.

## Problem

Only the reviewer has its own identity today: the per-developer App that `reviewer-setup` creates (`agent-reviewer-<you>[bot]`). The author, the orchestrator and the operator all post as the operator's account. Several mechanisms exist only to work around that:

- **Author watches ignore the operator.** An author-side `watch-pr.sh` filters out "your own login" (`git-workflow/references/review-rounds.md:20–23`). That login is the operator's, so a comment the operator leaves on the PR doesn't wake the author.
- **Body edits need their own wake mode.** `watch-issue.sh` has `--role=author --wake-on=body-edit` for "a body edit made under the operator's own login, which no login filter can single out" (`watch-issue.sh:45–47`).
- **Orchestrator posts look like the operator's.** The orchestrator's `Decision log:` rows post under the operator's login, so login filters can't tell them apart from the operator's comments or the author's (https://github.com/dbaggott/claude-plugins/issues/370).
- **Claims need extra markers.** `claiming.md:62` says "sessions run under the operator's account." That's why claims carry a session id and the `assigned:agent-session` label.
- **The operator can't approve.** The author's PRs are opened by the operator, and GitHub doesn't let a PR's author approve it. So only the reviewer bot can approve them.

## Goals

- The author, the orchestrator and the reviewer each act on GitHub under their own App bot login.
- Each App gets only the permissions its role needs.
- Setting up the new Apps is as easy as `reviewer-setup` is today: the Manifest flow plus installing the App.

## Non-goals

- **Isolating roles from each other on one machine.** See D4.
- **Changing who authors commits or who is assigned to issues.** See D2 and D3.
- **Release automation's App.** That's https://github.com/dbaggott/claude-plugins/issues/222, a separate actor already on its own App.
- **Implementing GitLab or Bitbucket backends.** That's https://github.com/dbaggott/claude-plugins/issues/149 and https://github.com/dbaggott/claude-plugins/issues/150. Designing for them is a goal here (R15–R18): no interface this work adds may be GitHub-shaped.
- **A Planner role.** See D11.

## Constraints

- **C1. The operator's login is shared by three actors today.** Checked by reading `claiming.md:33,62`, `review-rounds.md:20–23` (the author-role slug is "derived from your own account") and `watch-issue.sh:45–47`.
- **C2. App bot users can't be issue assignees.** Stated by the operator, 2026-10-15. Re-check: `gh issue edit <n> --add-assignee <slug>[bot]` on a scratch issue.
- **C3. No shipped script depends on who authored a commit.** Checked with `grep` over `dnbg-workflow/scripts`, `hooks` and `skills` at `c1a9acb`, anchors re-verified at `1e68dd1`:
  - every login filter matches the author of a comment, review or thread (`watch-pr.sh:416–427`, `lib-activity.sh:24–38`, `pr-threads.sh:122`, `watch-issue.sh:152–156`, `ready-set.sh:122`);
  - commits are read only for `oid` and `committedDate` (`pr-verdict.sh:101–109`, `review-rounds.md:11`).
- **C4. The "approve the most recent push" rule depends on who pushed, not who authored the commits.** GitHub's protected-branches docs say the push "must be approved by someone other than the person who pushed it" (https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches). This repo has the rule off (`require_last_push_approval: false`). Re-check with `gh api repos/<repo>/branches/main/protection`.
- **C5. A PR's author can't approve their own PR.** Observed: GitHub answers `422 … "Can not approve your own pull request"`, as quoted in https://github.com/dbaggott/claude-plugins/issues/152. `reviewer-setup/SKILL.md` relies on it. Re-check: `gh pr review <n> --approve` on a scratch PR you opened.
- **C6. Installation tokens expire after one hour.** See `SECURITY.md:174`, which cites GitHub's docs.
- **C7. App creation is already automated.** `reviewer-setup/bootstrap.py` builds the Manifest from `reviewer-setup/permissions.json`, and `reviewer/mint-token.sh` checks each minted token against that file. Both are verified present.
- **C8. Watchers poll under the operator's own `gh` auth.** `watch-pr.sh` and `watch-issue.sh` both run `unset GH_TOKEN`, so the long poll uses a credential that never expires.
- **C9. Today's write scripts deliberately post as the operator.** `claim-issue.sh:35` and `log-row.sh:31` run `unset GH_TOKEN`. R5 and R10 can't be met by a caller exporting a token; the scripts themselves have to take the role. Each decision-log row has **two write paths**, and both are in scope for R5 (`orchestrate/references/multi-issue.md:108`, "Every row is written twice"):
  - a `Decision log:` **comment** on the child, posted by the agent from a prose instruction with no command in the skill (`orchestrate/SKILL.md:239`, with its first line fixed at `triage.md:120–125`), so a sweep for `gh` text does not find it. These are the comments https://github.com/dbaggott/claude-plugins/issues/370 was about;
  - a row in the parent's **body**, written by `log-row.sh`, which rewrites the whole body.
- **C10. A push touching `.github/workflows/` needs the App's `workflows` permission.** `contents: write` alone is refused ("refusing to allow a GitHub App to create or update workflow … without `workflows` permission"). Seen in community reports, not in GitHub's own docs. Re-check by pushing a workflow edit from a scratch App without it.
- **C11. Git tries credential helpers in config order, and an empty `credential.helper` clears the list.** From `gitcredentials(7)`. A worktree-level helper therefore has to clear the list before adding its own entry, or the operator's global `gh auth git-credential` / osxkeychain answers first. The docs don't say how `credential.<url>.helper`, which `gh auth setup-git` writes, is ordered against plain `credential.helper`. Checked by https://github.com/dbaggott/claude-plugins/pull/436 on git 2.50.1: both forms land in one list in config-file order (system, global, local, worktree), and an empty entry of either form clears everything read before it. `tests/git-credential-as-role.bats` pins it with both global forms in place.
- **C12. A per-role bot identity costs a different amount on each forge** (from https://github.com/dbaggott/claude-plugins/issues/149 and https://github.com/dbaggott/claude-plugins/issues/150):
  - **GitHub:** one App per role, installed per account. Short-lived tokens are minted from a local key.
  - **GitLab:** one project or group access token per role, and each token is its own bot user. The tokens are long-lived. **They are unavailable on gitlab.com Free.**
  - **Bitbucket Cloud:** one repository access token per role per repository. That's 3 × N repos of setup. Whether workspace-level tokens avoid this, and at what tier, is unverified.
  - On every forge, the cheapest configuration may have no bot for the author and the orchestrator.
- **C13. The reviewer never falls back today.** `mint-token.sh` exits 1 when it isn't set up, and the reviewer stops. The `issues` consequence in `reviewer-setup/permissions.json` records why: a reviewer posting as the operator deadlocks, because the author's watch excludes that login.

## Requirements

### Setup and minting

- **R1.** Setup creates the App for any chosen subset of roles (`reviewer`, `author`, `orchestrator`) from that role's permissions file, in one run, and stores each App's credentials in its own config directory. The setup skill keeps the name `reviewer-setup`, with its prose generalized to role Apps ([Q-b on 425](https://github.com/dbaggott/claude-plugins/issues/425#issuecomment-6399849299)).
- **R2.** An existing reviewer setup at `~/.config/dnbg/reviewer/`, or one set through `DNBG_REVIEWER_*` variables, keeps working with no re-setup.
- **R3.** Minting takes a role. Each role keeps today's choice of key source, its order (environment variable, then key command, then file), its file-permission checks and its check of granted permissions. The environment variables are `DNBG_<ROLE>_*`, and `DNBG_REVIEWER_*` is unchanged. `DNBG_<ROLE>_SLUG` stands in for `config.json`'s `slug`, as `_APP_ID` does for `app_id`, so a role set up through variables alone still has a login ([425-D2](https://github.com/dbaggott/claude-plugins/issues/425#issuecomment-6399872948)).
- **R4.** No minted token is written to disk, to git config or into a remote URL, and none is printed to logs.

### Orchestrator

- **R5.** Every GitHub write the orchestrator makes (decision-log rows, labels, comments) posts under the orchestrator App. A tracking issue's closeout splits by what each write is ([Q-a on 426](https://github.com/dbaggott/claude-plugins/issues/426#issuecomment-6400460795), [as applied on 427](https://github.com/dbaggott/claude-plugins/issues/427#issuecomment-6422150530)): the parent-body edits, log rows and disposition question are the orchestrator's, while the closeout PR's writes and its follow-up filing are the author's (R8). A friction-log relay on the parent is accepted from the operator's, the author's or the orchestrator's login, since a child's author may relay too ([correction on 427](https://github.com/dbaggott/claude-plugins/issues/427#issuecomment-6422163715)).
- **R6.** The orchestrator App has no `contents` permission. It needs `issues` write. Metadata read is mandatory. It has no `pull_requests` permission: its PR reads stay under the operator's own `gh` auth ([426-D2](https://github.com/dbaggott/claude-plugins/issues/426#issuecomment-6421875152)).
- **R7.** No watch excludes the orchestrator in the bot tier. Orchestrator posts, `Decision log:` comments included, wake every watch on the object they land on, as R20 tabulates. The operator's own comments wake the author's watches.

### Author

- **R8.** The author's pushes, PR creation, PR comments and thread replies, claim comments and filed issues post under the author App. A CI rerun (`gh run rerun`) stays under the operator's own `gh` auth, since it needs `actions: write`, which R12 withholds ([427-D1](https://github.com/dbaggott/claude-plugins/issues/427#issuecomment-6400441341)).
- **R9.** Commits stay authored by the operator: `user.name` and `user.email` are unchanged, and so is the Co-Authored-By trailer.
- **R10.** Claims still assign the operator and still carry `assigned:agent-session` and the session-id comment. The comment posts under the claiming role's App: the author's when a session resolves the issue itself, the orchestrator's when `orchestrate` claims it for its author (R5). The operator's login comes from the resolver's **operator** answer (R15), never from `@me`, because `@me` resolves against whatever credential is in place: under a role token that is either the bot, which C2 says can't be assigned, or no user at all. Which of the two `gh` does is unverified, and either breaks the claim. `claim-issue.sh`'s "held only by you" comparison (`claiming.md`, the `FOREIGN claim=none` case) uses the same answer.
- **R11.** Pushes keep working in a session that outlives a token. Each push uses a freshly minted token, through a git credential helper scoped to the worktree.
- **R12.** The author App has `contents` write, `pull_requests` write, `issues` write and `workflows` write (C10), plus read on `checks`, `actions` and `statuses`. It has no administration permission.
- **R13.** Author-side watches exclude the author bot's login, not the operator's, so a comment from the operator wakes the author. The `--wake-on=body-edit` mode is kept in both tiers, as recorded on https://github.com/dbaggott/claude-plugins/pull/436: the watch reads only `lastEditedAt`, never who edited, so even in the bot tier no login filter can single out an operator edit.

### Cross-cutting

- **R14.** `SECURITY.md` and `docs/configuration.md` describe each App's permissions, what a leaked key can reach, and how to rotate the key.

### Forge seam and fallback

- **R15.** One resolver answers every question about a role's identity, so nothing else knows the forge's credential mechanism. It takes a role and a repo, given as a remote URL or `host/namespace/repo`, never a bare `<owner>`, because GitLab namespaces nest and GitLab can be self-managed. It answers three questions:
  - **credential:** run a command with the role's credential in place;
  - **login:** print the role's login in every spelling the forge uses;
  - **operator:** print the operator's own login, read under the operator's own forge auth with no role credential in place.

  Default shape, which https://github.com/dbaggott/claude-plugins/issues/425's criteria fix: `scripts/as-role.sh <role> <repo> -- <cmd…>` for **credential**; `scripts/as-role.sh --login <role> <repo>` and `scripts/as-role.sh --operator <repo>` print one result line, `result=OK login=<login> fallback=<none|unconfigured>`. On GitHub, `login` is the App slug, and consumers add `[bot]` as `lib-activity.sh` already does. The **credential** form prints its result line on stderr, `as-role.sh: result=OK as=<login> fallback=<…>`, leaving stdout to the command, and exits 125 without running the command when the resolver itself fails ([425-D3](https://github.com/dbaggott/claude-plugins/issues/425#issuecomment-6399873230)). A fourth, internal call, `as-role.sh --fallbacks`, prints `result=OK roles=<role,…|none>` from config presence alone, with no network, for R18's notice ([425-D1](https://github.com/dbaggott/claude-plugins/issues/425#issuecomment-6399872642)).
- **R16.** Fallback to the operator happens only when the role has **no configuration** for that forge. If a role is configured but its credential fails (a failed mint, a revoked grant, an expired token, a key command that prints nothing), the call is an error and never runs as the operator.
- **R17.** Only the author and orchestrator fall back (D9). The reviewer refuses (C13). The resolver also refuses any configuration where two roles resolve to the same login, except that the author and the orchestrator may both resolve to the operator. Each role's policy is a top-level `"fallback"` key in `roles/<role>/permissions.json`, `"operator"` or `"refuse"`, with absent meaning refuse, because the file already is the role's data and refusing is the safe default ([Q-a on 425](https://github.com/dbaggott/claude-plugins/issues/425#issuecomment-6399849101)).
- **R18.** Every write script's result line carries `as=<login>`, plus `fallback=unconfigured` when it ran as the operator. Each script gains this in the child that gives it `--as`: `as-role.sh` and `claim-issue.sh` in https://github.com/dbaggott/claude-plugins/issues/425, `log-row.sh` in https://github.com/dbaggott/claude-plugins/issues/426. `claim-issue.sh --as=<role>` is role-generic, because the orchestrator and the author both claim through it; https://github.com/dbaggott/claude-plugins/issues/426 and https://github.com/dbaggott/claude-plugins/issues/427 route their own claim call sites through it. A SessionStart hook prints one line naming each role that falls back. The hook reads config presence only, through `as-role.sh --fallbacks` (R15), and makes no network call.
- **R19.** Watchers take the login they exclude from the resolver's **login** answer, not from a hand-derived `--slug` (before this work the author's was `gh api user` at `watch-pr.sh:124–127`, and the reviewer's was read from its `config.json` at `pr-threads.sh:93`). When a role falls back, that answer is the operator's login, so the earlier behavior returns exactly. The answer feeds `--slug` alone. This work passes no `--exclude-login`. An author-role watch given no `--slug` asks the resolver itself, so its arm sites pass nothing ([427-D3](https://github.com/dbaggott/claude-plugins/issues/427#issuecomment-6400441760)).
- **R20.** Each watch excludes exactly one login: its own role's. In the fallback tier the author's login is the operator's, so the author's watches also skip orchestrator posts, as they did before this work.

  | Watch | Where it is armed | Excludes (bot tier) | Excludes (fallback) | Orchestrator posts wake it? |
  | --- | --- | --- | --- | --- |
  | Author PR, `watch-pr.sh --role=author` | `git-workflow` `review-rounds.md`, `merge-wait.md` | author bot | operator | yes: they are addressed to the author |
  | Author issue, `watch-issue.sh --role=author` | `issue-workflow` `spec-review-rounds.md` | author bot | operator | yes: a decision row can change what the author builds |
  | Issue-reviewer, `watch-issue.sh` | `issue-reviewer` `rounds.md` | reviewer bot | reviewer bot | yes (unchanged) |
  | Reviewer PR, `watch-pr.sh --role=reviewer` | `reviewer` `SKILL.md` | reviewer bot | reviewer bot | yes (unchanged) |
  | Reviewer issue and tracking, `watch-issue.sh` | `reviewer` `issue-mode-wait.md`, `issue-mode-tracking.md` | reviewer bot | reviewer bot | yes: https://github.com/dbaggott/claude-plugins/issues/370's default, since a decision row can change what the reviewer grades |

  `ready-set.sh --slug` (`orchestrate` `multi-issue.md:51`) matches the reviewer's login rather than excluding it, and takes it from the same **login** answer. The orchestrator arms no forge watch; it waits on its subagents.
- **R21.** The hooks that parse command lines, starting with `check-issue-create.sh`, recognize an `as-role.sh … --` prefix as they recognize `env -u GH_TOKEN`.

## Decisions

- **D1. One App per role, created by each developer.** Because: a login per role gives honest attribution and filters by identity instead of message text, and each role's permissions can be kept to what it needs. Keeping the key on the developer's machine matches `reviewer-setup`'s "no shared secret" posture. Revisit if: the plugins need a centrally managed bot that several developers share.
- **D2. The operator stays the commit author; the author bot only pushes and opens PRs.** Because: the operator is responsible for work done under their supervision. C3 and C4 show nothing breaks: no script depends on who authored a commit, and approval rules depend on who pushed. Revisit if: none identified.
- **D3. Claims keep assigning the operator.** Because: App bot users can't be assignees (C2). Revisit if: GitHub allows App bots as assignees.
- **D4. Separate Apps are not a security boundary between roles on one machine.** Because: every role's key sits under the same OS user, and any agent can mint any role's token. What this buys is attribution and narrower permissions per call, not isolation. Revisit if: roles start running under separate users or sandboxes.
- **D5. There is no shared "agent" App for the author and orchestrator together.** Because: telling them apart by a body prefix such as `Decision log:` repeats today's mistake of identifying an actor by its text instead of its login. Revisit if: real setup cost for other users of the plugins outweighs the separation.
- **D6. `issue-reviewer` uses the reviewer App, and there is no fourth role.** Because: it is the reviewer role acting on issue bodies, and orchestrate's subagents already map onto the author and the reviewer. Revisit if: a new kind of actor posts to GitHub. (D11 covers the Planner case specifically.)
- **D7. The seam is a role-identity resolver, not a "token".** Per https://github.com/dbaggott/claude-plugins/issues/21, setup is per-forge and the use-time contract is shared, and this work adds a third role to that pattern. Each forge backend turns `(role, repo)` into a credential and a login: a JWT mint on GitHub, a stored access token on GitLab and Bitbucket. Key sourcing (env var, then key command, then file; R3) carries over unchanged, because on the token forges the "key" is the token itself. Because: a `mint-token.sh <owner>` interface bakes in two GitHub-only assumptions, minting and a flat owner. Revisit if: a forge needs more than a credential and a login to stand in for a role.
- **D8. Roles act through a role-scoped exec, not per-command env and not a `gh` shim** (resolves Q4). There are three paths to one resolver:
  1. **Adapter write scripts take `--as=<role>`** and resolve the credential internally. These are `claim-issue.sh`, `log-row.sh` and the write scripts https://github.com/dbaggott/claude-plugins/issues/149 is moving out of skill prose. This is the target end state.
  2. **For raw commands still in skill prose**, a wrapper: `as-role.sh <role> <repo> -- <cmd…>`. It resolves the forge, puts the credential where that forge's tool reads it (`GH_TOKEN`, `GITLAB_TOKEN`) and execs the command. The reviewer's `export GH_TOKEN="$(mint)"` idiom moves to this wrapper as well.
  3. **`git push` goes through a worktree-scoped credential helper** that calls the resolver (R11, C11). The git credential protocol is forge-neutral, so this path needs no per-forge code at the call site.

  Because:
  - **Per-command `GH_TOKEN=$(mint) gh …`** is the https://github.com/dbaggott/claude-plugins/issues/152 bug class repeated at every write site. The author has roughly 50 `gh` sites across `git-workflow` and `issue-workflow`, and the variable name is GitHub-specific.
  - **A `gh` shim on PATH** can't know which role is calling. It is gh-only, so it gives the other forges no seam. It is also invisible in transcripts.
  - **Exec makes mint and use one process,** so the token can't silently fail to reach the command.

  Known cost: hooks that parse command lines, such as `check-issue-create.sh`, have to recognize the `as-role.sh … --` prefix, as they already recognize `env -u GH_TOKEN`. Revisit if: the harness starts persisting env between tool calls.
- **D9. The author and orchestrator fall back to the operator with a notice. The reviewer never does** (resolves Q1). Validated against the other forges: C12 shows that on gitlab.com Free, and on Bitbucket without per-repo setup, falling back may be the **permanent** configuration, not a migration aid. So:
  - The fallback is a supported tier, and the earlier workarounds remain its mechanisms: the session-id claim, the `--wake-on=body-edit` mode and the operator-login exclusion.
  - All of this follows from R19. The login answer in fallback is the operator's, so no watcher needs a mode switch.
  - **Mixed tiers** (author on a bot, orchestrator on the operator, or the reverse) still let orchestrator posts wake the author, which R20 wants. The degraded case is **full fallback**: the author's operator-login exclusion also hides orchestrator posts from it. That is the behavior from before this work, and it causes no deadlock. It's accepted and documented ([decision-log row for 423-O8](https://github.com/dbaggott/claude-plugins/issues/423#issuecomment-6370462648)). Silent fallback is prevented by R16 and R18. The reviewer is excluded because a reviewer on the operator's login is the deadlock in C13 and cannot approve under C5.

  Revisit if: a forge needs a comment-declared reviewer identity (the degraded tier in https://github.com/dbaggott/claude-plugins/issues/149). That is its own design.
- **D10. Roles are data.** Each role is a name, a permissions file (`dnbg-workflow/roles/<role>/permissions.json`, which `reviewer-setup/permissions.json` moves to; the resolver finds it at `$(dirname "$0")/../roles/<role>/permissions.json`) and a config directory. Setup, minting and the resolver loop over roles and contain no per-role code. Because: adding a role later (D11) should be a permissions file plus prose, not a refactor. Revisit if: a role needs different behavior from the resolver beyond its fallback policy.
- **D11. No Planner role yet. Issue filing and spec edits stay with the author.** An identity earns its setup cost when one of three things needs it:
  - **a watcher has to tell two actors apart on the same object at the same time.** Planning and implementing happen in sequence, and the handoff between them is gated by `issue-reviewer` (reviewer bot) and the operator, who already have distinct logins. No watcher needs a planner separated from an implementer.
  - **an approval rule has to treat them differently.** None does.
  - **a permission split would actually bind.** It wouldn't: the implementer needs `issues: write` for claims and comments, and GitHub's `issues: write` also allows editing any issue body.

  The real risk in merging the two is that the implementer edits the acceptance criteria it is being measured against. A separate login doesn't prevent that. It would only make it legible, and the body's edit history plus `orchestrate`'s `design-change.md` path is the better control. Issues filed during an interactive design session also post as the author (Q6), so there is one rule. Revisit if: spec-stage and implementation-stage writes start landing on one object at the same time (such as an implementer replying in a spec-review round), or implementers editing specs mid-flight shows up in retrospectives.
- **D12. Credentials live in one directory per role, `~/.config/dnbg/<role>/`.** Because: the reviewer's existing path already has that shape, so R2 needs no migration. Each non-GitHub backend chooses its own layout under the role directory when it is built; this work fixes only the role-directory level. Revisit if: a forge backend needs credentials that aren't per role.
- **D13. `mint-token.sh` moves to `dnbg-workflow/scripts/` as the GitHub backend behind the resolver (D7).** Because: every role uses it. Skill references are updated in the same PR, with no forwarding stub, because skills invoke it by a relative path that ships with the plugin. Revisit if: none identified.

## Open questions

- **Q1. If the author or orchestrator App isn't set up, does that role fall back to the operator's account?** Decided 2026-10-23 (D9).
- **Q2. Where do credentials live?** Decided 2026-10-23 (D12).
- **Q3. Does `mint-token.sh` move to `dnbg-workflow/scripts/`?** Decided 2026-10-23 (D13).
- **Q4. Are role tokens passed per command (`GH_TOKEN=… gh …`) or through a `gh` wrapper?** Decided 2026-10-23 (D8).
- **Q5. Should a Planner role be added?** Decided 2026-10-23 (D11).
- **Q6. Once the author App exists, should issues filed during an interactive design session still post as the operator?** Decided 2026-10-23 (D11).

## End-to-end acceptance criteria

- **A1.** One orchestrated run against a scratch issue, recorded on the closeout PR, shows each of the following:
  - the claim comment comes from the orchestrator bot, which claims for its author (R5, R10);
  - the PR and every push come from the author bot;
  - every commit is authored by the operator;
  - the decision-log rows come from the orchestrator bot;
  - the review comes from the reviewer bot;
  - a comment from the operator on the PR wakes the author.

  Contributes: https://github.com/dbaggott/claude-plugins/issues/425, https://github.com/dbaggott/claude-plugins/issues/426, https://github.com/dbaggott/claude-plugins/issues/427, through https://github.com/dbaggott/claude-plugins/pull/434, https://github.com/dbaggott/claude-plugins/pull/437 and https://github.com/dbaggott/claude-plugins/pull/436. Recorded by the closeout PR's author, who runs it before the project review. Recorded run: the A1 section of https://github.com/dbaggott/claude-plugins/pull/441. Proves that each role's GitHub writes post under its own login and that the operator's comment wakes the author. Re-run after a change under `dnbg-workflow/scripts/`, `dnbg-workflow/roles/`, the setup skill, or the `orchestrate`, `git-workflow`, `issue-workflow` or `reviewer` skills, unless the PR's record shows the change leaves that behavior as it was.
- **A2.** On a repo that requires one approval, the operator's approval of a PR opened by the author bot counts in `reviewDecision`. Contributes: https://github.com/dbaggott/claude-plugins/issues/427, which records the run on its own PR. Recorded run: the A2 section of https://github.com/dbaggott/claude-plugins/pull/436. This repo can't host the run, since it has `required_approving_review_count: 0`. Decided 2026-10-25 ([427-D2](https://github.com/dbaggott/claude-plugins/issues/427#issuecomment-6400441534)): the run uses the existing testbed `dbaggott/dnbg-watch-testbed`, whose `main` protection already requires one approving review (it is private, and protection is already in place there), with the author App installed on it. https://github.com/dbaggott/claude-plugins/issues/427's author runs the operator's approval with `gh pr review --approve` under the operator's own `gh` auth. Proves the operator can approve the author bot's PR (C5 no longer blocks them). Re-run after a change to `as-role.sh`, the author's credential helper, or how `git-workflow` opens and pushes a PR, unless the PR's record shows the change leaves that behavior as it was.

## Where it was built

| Child | Covers | Merged PR |
| --- | --- | --- |
| https://github.com/dbaggott/claude-plugins/issues/425 Role resolver, setup and minting; role-generic `claim-issue.sh --as`; reviewer and issue-reviewer onto the resolver | R1, R2, R3, R4, R10, R14, R15, R16, R17, R18, R19, R20, R21 | https://github.com/dbaggott/claude-plugins/pull/434 |
| https://github.com/dbaggott/claude-plugins/issues/426 Orchestrator App: `roles/orchestrator/`, `log-row.sh --as`, `Decision log:` comments, orchestrated claims | R1, R4, R5, R6, R7, R10, R14, R16, R17, R18, R20 | https://github.com/dbaggott/claude-plugins/pull/437 |
| https://github.com/dbaggott/claude-plugins/issues/427 Author App: `roles/author/`, author writes, push credential helper, author watches; records A2 | R1, R4, R7, R8, R9, R10, R11, R12, R13, R14, R16, R17, R18, R19, R20 | https://github.com/dbaggott/claude-plugins/pull/436 |
