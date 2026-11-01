---
name: git-workflow
description: How to change any tracked file in a covered repo — worktree, draft PR, review rounds, merge handoff, post-merge cleanup. Load before you edit, write, or modify any tracked file in a covered repo (application code, skills, plugins, docs, configs, tests — anything that would show up in `git status`), and when opening a PR (including pairing PRs across repos for one multi-repo change), marking one ready, watching for or addressing review feedback, or cleaning up after a merge. The trigger is a tracked file changing, not the user's choice of words.
---

# Git workflow

This is the standard flow for any code change in a covered repo — one whose
`origin` belongs to an account in this plugin's `owners` setting. Never modify
the main checkout directly; always work in a worktree.

## This flow is GitHub-only

Every step below drives `gh`, so on another forge it cannot run at all. Before
step 1, read the host of the repo you are about to change:

```bash
git remote get-url origin
```

**If the host is not `github.com`, stop and decline.** Say that this flow is
GitHub-only, name the host you found, and fall back to the flow the project
already uses, without running a `gh` command against it first or translating
the flow to `glab` or another forge's CLI.

Not a decline: **no `origin`** makes no forge claim, so proceed without assuming
GitHub and let the operator direct; with **several remotes**, `origin` decides,
as the enforcement hooks do. Declining is per skill: `velocity-tradeoff`
applies on any forge.

## Starting a change

**If this work originates from an existing issue** (the task named an issue number or URL), load `issue-workflow` and claim the issue *before* the steps below — claiming and the freshness probe come before the worktree, not after. Don't let "the work ends in file edits" pull you straight here; issue pickup is the entry action, this flow is just the destination.

1. `git fetch origin` — fetches all refs so later diffs against other branches don't surprise you with stale data.
2. `gh pr list --repo <repo> --state open` — if any open PR might touch the files you're about to change, check its diff (`gh pr diff <num>`) and either coordinate or hold off. Independent staleness check from the fetch above: that one catches a stale base, this one catches concurrent work — without it, two PRs against the same node in the same file can both rebase cleanly and one becomes a wasted no-op the moment the other merges.
3. Re-read any files you touched in a prior session — code may have changed.
4. `git worktree add .worktrees/<branch-name> -b <branch-name> origin/<default-branch>` — the default branch comes from the settings read below; don't assume `main`. If the change spans repos, the branch name is the pairing key; read `references/multi-repo.md` before picking it. Then point the worktree's pushes at the author role, per "Acting as the author" below:

   ```bash
   "<skill-dir>/../../scripts/git-credential-as-role.sh" --install author <worktree-path>
   ```

   Run it on every worktree you work in, one you take over or continue included. It reads `result=OK`; on `result=ERROR`, stop and say what it named.

   When your prompt names a branch to stack on, read `references/stacked-branch.md` before this step's calls, on a worktree or PR you continue too: it changes this step, step 7's ranges, step 8, and what step 9 keeps in the description.

   In a sandboxed Claude Code session, read `references/sandbox.md` before this step's calls, on a worktree you take over or continue too.
5. Make changes in the worktree.
6. Commit.
7. **Self-review the branch, and address what it finds** — before pushing. When the issue declares an operator check before review, that check comes first and moves the push and the draft PR ahead of this step: read `references/operator-check.md`.
   - **Against the standards** — the set the always-on "Coding standards stack" rule had you load. `git -C <worktree-path> diff origin/<default-branch>...<branch-name>`, where `<worktree-path>` is the absolute path of the worktree step 4 created, read against those files re-opened rather than recalled: you wrote the diff from memory of them, so memory is what needs checking. Where a standard names something countable, grep the diff for it instead of eyeballing.
   - **For defects, with the harness's code-review tool.** In Claude Code that is `/code-review <worktree-path> origin/<default-branch>...<branch-name>`. The tool runs git from the session's working directory, which may be the main checkout, where `HEAD` is not your branch, or another repo, where your branch does not exist; the path points it at the worktree. Name both ends of the range too: the branch's upstream stops meaning the base once the branch is pushed. Leave the effort level to whatever the operator last chose, except never `ultra`, which is a billed cloud run the operator starts themselves. Don't pass `--fix` — findings need triage, not blanket application. The tool may run in the background and return its result later as a notification: wait for that result before step 8. A dispatched author that ends its turn to wait says in that turn's report that it is waiting on the background review. A result that is an error rather than findings ends the wait, and the standards pass becomes the whole stage, as below.

   Fix a finding in this branch by default. Decline one that is wrong or out of scope, with a one-line reason. One pass: the fixes go to the reviewer with everything else rather than back through the tool.

   The standards pass is the whole stage when the harness has no code-review tool, or when every hunk of the diff is generated or data files with no logic in them, prose no agent follows as instructions, or a rename the issue specifies in full. For those three, read `references/defect-pass-exemptions.md`, which says what each covers, before you skip the tool. Say the defect pass was skipped, and why, when you announce the PR and in the PR description.
8. Push, and **open the PR as a draft**, its description drafted at `<file>`, which is `<draft directory>/pr-body.md` (`references/draft-files.md`):

   ```bash
   git -C <worktree-path> push -u origin <branch-name>
   "<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
     gh pr create --draft --repo <owner>/<repo> --head <branch-name> --title "<title>" --body-file <file>
   ```

   On a stacked branch, `references/stacked-branch.md` adds a flag to this call and a step after it.
9. After each commit, push, and update the PR description if needed so it reflects the **as-built** state, written per **"Writing the PR description"** below — we do not narrate the development history in the description. On a stacked branch, keep the lines `references/stacked-branch.md` names. The new description goes in your draft directory too, per `references/draft-files.md`: `"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- gh pr edit <number> --repo <owner>/<repo> --body-file <file>`.
10. **Announce the PR and call `AskUserQuestion`** to ask whether to send it to review — see "After opening a draft PR" below for the exact two-option picker. Do **not** mark it ready yourself, and do **not** substitute a prose question for the picker. Without `AskUserQuestion`, follow `<skill-dir>/../issue-workflow/references/delegated.md`.
11. When the operator picks "Send to review" (or later says "ready" / "go"), mark it ready (`"<skill-dir>/../../scripts/as-role.sh" author <repo> -- gh pr ready <number> --repo <repo>`) and start watching for the first review — see `references/review-rounds.md`, which carries the watch, and `references/watch-results.md` for what each of its results means. A review that comes in goes to `references/review-received.md`, findings to `references/review-findings.md`, and a clean verdict to `references/merge.md` for the handoff.
12. Never merge. Only a human merges PRs.

Worktrees live in `.worktrees/` inside the repo. Ensure `.worktrees` is in `.gitignore`.

**`.worktrees/` is the default, not a constant.** It is configurable, so if a `dnbg-workflow` note at session start names a different worktree root, that note wins and every `.worktrees/` in this skill means the root it names — including the `git worktree add` in step 4 and the `git worktree remove` in the post-merge cleanup. With no such note, the literal above is what this session uses.

**Concurrent work is the norm — other worktrees are not a finding.** `.worktrees/` routinely holds branches from other sessions, other agents, and the operator's own in-flight work. Their presence is expected, needs no report, and is not evidence anything is wrong. Never touch one you didn't create.

What *is* worth raising is a concrete collision: step 2's open-PR check, or a sibling worktree, shows work landing on the same files or the same design surface as yours. Flag that with the specific overlap — "`<branch>` also edits `src/auth.ts:40-70`" — so the operator can decide whether to coordinate. The signal is the conflict, not the parallelism.

## Acting as the author

Every write you make on the forge goes up as the **author role**: the PR, its
description and state, comments, thread replies and resolutions, labels, and
the issues you file, edit or comment on. Each runs through the role resolver:

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- gh …
```

It runs the one command with the author App's token in place, or as your own
account when no author App is set up; its stderr line, `as-role.sh: result=OK
as=<login> fallback=<none|unconfigured>`, says which. Prefix the write itself,
not a block around it: reads (`gh pr view`, `gh pr diff`, a `gh api` GET) run
under your own auth. When the resolver refuses, it exits 125 without running the
command, after `as-role.sh: result=ERROR reason=<reason>` and what to do. A
`credential` refusal means the author App is set up and its token could not be
had; fix what the message names (`reviewer-setup` covers installing an App on
an account) rather than running the command another way. A configured author
never falls back to your account.

Pushes take no prefix: step 4's `--install` configures the worktree's own git
config with a credential helper that asks the resolver on every push, and turns
an SSH `origin` into an HTTPS push URL so the helper is asked at all. The main
checkout keeps your own credential. Commits stay yours: nothing changes
`user.name`, `user.email` or the Co-Authored-By trailer. With no author App and
an SSH `origin`, pushes then go over HTTPS with `gh`'s own token, which needs
the `workflow` scope to push a change under `.github/workflows/`: `gh auth
status` lists the scopes, and `gh auth refresh -s workflow` adds it.

## Know the repo's merge settings

Later steps depend on how this particular repo is configured: which branch to fork from, how the merge command is composed, whether a push dismisses an approval, and what the post-merge cleanup still has to do. **Read them, don't assume them** — these settings vary between an org's repos and a personal account's, and between two repos in the same account.

Read once per repo, early:

```bash
gh api repos/<owner>/<repo> --jq \
  '{default_branch, allow_auto_merge, allow_squash_merge, allow_merge_commit,
    allow_rebase_merge, delete_branch_on_merge}'
```

| Field | What it decides |
| --- | --- |
| `default_branch` | what you branch from and target — not necessarily `main` |
| `allow_auto_merge` | whether `gh pr merge --auto` works at all |
| `allow_squash_merge` / `allow_merge_commit` / `allow_rebase_merge` | which merge flag to hand the operator, and whether the branch tip ends up an ancestor of the base (which decides `-d` vs `-D` locally) |
| `delete_branch_on_merge` | whether the remote branch still needs deleting after the merge |

Throughout this skill and its references, `<skill-dir>` is the **Base directory** announced when the skill loads — not the directory of the file you are reading. The scripts sit beside the skills rather than inside one, so the same `../../scripts/` reaches them from every skill that shares them.

**Whether HEAD is approved** is `pr-verdict.sh`'s answer, never branch
protection's: read `references/approval.md` before telling the operator a PR is
ready to merge, or merging one.

For a multi-repo change, read this **per repo**. Siblings genuinely differ, and a setting borrowed from the wrong one produces a merge command that fails or a cleanup step that silently does nothing.

## Writing the PR description

The description reflects the **as-built** state, rewritten after each commit — and every claim in it must be *true and earned*. A reviewer who catches one inflated claim discounts the whole description, so the asymmetry is stark: under-claiming costs nothing, over-claiming costs trust.

- **Name what you verified, and how — don't imply more.** "Typechecks (`tsc`)" and "CI green" are not "tested"; "eyeballed one case on dev" is not "verified end-to-end." State the check you actually ran; if you didn't run one, don't phrase the body so it reads as if you did.
- **Don't assert coverage you don't have.** No unit runner for a file? Say its helpers are covered by typecheck + manual, not that they're "tested." Never describe intended or aspirational tests as existing ones.
- **Don't state impact without evidence.** Performance, cost, "fixes X for all inputs" — back it with the measurement or the reasoning, or hedge it. A confident-sounding number with no source is an over-claim.
- **Claim only the scope you checked.** The over-claim usually starts one step earlier, as an unexamined assumption written up as fact: that a change generalizes, that it fixes the root cause (not just the symptom you reproduced), that the correlation you saw is the cause, that nothing else is affected. Verify the assumption, or state the scope you actually verified ("fixes the observed case; other inputs unchecked"; "removes the symptom — root cause not confirmed"). An assumption is not a result.
- **Surface gaps, not just wins.** Known limitations, unverified branches, and deferred follow-ups belong in the body — these are as-built facts about the result, not the development narrative ruled out above; omitting them reads as "all handled," and the next reader inherits the surprise.

Draft the description as `pr-body.md` in your draft directory, per
`references/draft-files.md`.

When unsure whether a claim is earned, weaken it or cut it — a description a reviewer can trust line-for-line is worth more than an impressive one they have to second-guess.

**Claim less, rather than more precisely.** The bar above pushes toward accuracy, and accuracy pushes toward checkable detail — a count, a percentage, a file list. Each of those is something a reviewer can verify, and verifying it costs a round whether or not it was worth stating. Ask what they do differently for having it: a number that scopes the diff earns its place; a number that only describes the work does not. Precision about a quantity that moves is the worst case, since it is guaranteed to drift where a true loose claim survives the next commit.

**If the only fix is to correct the message, the message was the defect.** When a finding's whole remedy is editing prose that ships — this description, a commit message, a changelog fragment — and nobody acts on the detail, cut the claim instead of correcting it. Correcting keeps the liability and spends the round again the next time it drifts.

**Where the number *is* the evidence, keep it and bound what it supports.** A measurement an argument rests on cannot be loosened away without taking the argument with it. State what it does and does not establish — "observed once in nine cycles, which is a floor on the rate rather than an estimate of it" — so a reader cannot over-read it and a later count cannot falsify a claim you never made. That is the third option whenever cutting would cost the point.

**If a `## dnbg-workflow <version>` note appeared at session start, end the description with the version stamp it names:**

```
<!-- dnbg-workflow <version> -->
```

Re-state it on every rewrite, with the rewriting session's version. With no note, leave it off, taking the version from nowhere else.

## Draft files

Every PR description, issue body, comment and review you draft in a file before
posting it goes in your draft directory, and every agent you dispatch gets one:
read `references/draft-files.md` before your first draft or dispatch.

## Multi-repo changes

When one logical change spans repos, or a change turns multi-repo midway, read
`references/multi-repo.md` before picking the branch name or opening the next
repo's PR: it pairs the PRs by branch name and title tag, and says which one
closes the issue.

## Project tag

A PR resolving an issue whose title starts with a `[<slug>]` tag — a tracking issue or one of its children, per `issue-workflow`'s `references/tracking-issue.md` — carries the same tag: `[<slug>] <title>`. A multi-repo PR already carrying `[<branch-name>]` keeps that tag and gets no second one. Name the branch of a project-tagged PR something other than the bare slug: a title tag equal to the branch name is what marks a multi-repo sibling.

## After opening a draft PR

**Before this picker, if you made a substantive design change mid-implementation** — a departure from the approach agreed at pickup (the issue's "Proposed approach", or, for a PR with no issue, whatever you and the operator settled on in chat), a contract/interface change, anything a reviewer would be surprised by — surface that change and its rationale in chat *first* (without `AskUserQuestion`, as a `Delegated question:` of its own per `issue-workflow`'s `references/delegated.md`, posted before the send-to-review question and with the built state as one of its options), per `issue-workflow`'s `references/resolving.md`, "Surface design changes that emerge mid-implementation". The operator must learn the design moved before review and manual testing run against it, not discover it inside the review. This applies to any PR — without an issue, the agreed design lives in the chat thread instead of an issue body.

Announce the draft PR with its full URL and the self-review's outcome — what it fixed, in a line, and each finding you declined with its reason, since those are what the operator is deciding to send on. Process friction that did not stop the task is not part of this announcement and is not offered for filing here: it waits for your close-out, per `<skill-dir>/../findings-review/references/report.md`'s "At a close-out". Then call `AskUserQuestion` with two options (the tool auto-appends "Other" for anything else). Without it, ask the same question per `<skill-dir>/../issue-workflow/references/delegated.md`:

1. **"Send to review (Recommended)"** — "Mark the PR ready and watch for the first review."
2. **"Not yet"** — "Leave it in draft; say 'ready' whenever you want it reviewed."

On "Send to review", run the flow in `references/review-rounds.md`. On "Not yet", leave the PR in draft and carry on — the operator saying "ready" later re-enters the same flow.

Don't offer "or run `gh pr ready` yourself" as an option. The watch and the review handling only fire when you run the mark-ready step, so an operator who does it out-of-band gets no follow-up from you and has been told otherwise.

## Issue and PR references

Full GitHub URLs, always — per the always-on rule "Reference issues and PRs by full URL". The rationale and the memory-file exception live there.

## When a PR merges

The post-merge cleanup is in `references/post-merge.md`, and it runs before any new work. Reach it from `references/merge-wait.md` when the merge lands, from `references/watch-results.md` when the review watch reports the PR closed, and straight from here when you are simply told a PR merged — a resumed session, or one that only ever opened the PR.

## After rebase or merge

Always review incoming changes after rebasing or merging. Don't assume the prior state is still accurate — read the changed files before answering questions about them.

## Related skills

Optional: if your project has no coding standards of its own, the separate
`dnbg-practices` plugin carries them (`/plugin install dnbg-practices@dnbg`).
