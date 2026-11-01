# Orchestrate: stacked mode

Part of the `orchestrate` skill. Read this with `references/multi-issue.md`
when a tracking issue's run is in stacked mode, which this file says how to
enter. It changes that file's loop where it says, and nothing else.

When the operator cannot merge for a while, every child waits on its blocker's
merge. Stacked mode keeps the run moving: a child whose one blocker has an
approved PR is based on that PR's branch instead of waiting.

## Entering it

It is on when the operator's prompt says so, such as "orchestrate `<URL>`,
stacked" or "I'm away: stack the PRs". Record it before the first dispatch as
a `decided` row on the parent with ID `Stacked mode`, **Question** `none, asked
at dispatch`, **Answer** `On.`, and **Basis** `operator`, in session
(`references/triage.md`, "The row"). It changes no design, so its table row is
written as `applied`. On start, the parent's latest `Stacked mode` row says
whether the mode is on.

With `AskUserQuestion`, offer it once, at the first merge handoff you relay
whose PR resolves a blocker of a `waiting` child: "Merge now, or stack
`<child URL>` on this branch?". Record the answer the same way, with
**Question** naming that PR and **Answer** `On.` or `Off.`. Without
`AskUserQuestion`, a prompt that says nothing about it means the mode is off.

## What it changes in the loop

- **Step 3** passes `--stacked` to `ready-set.sh`. A `ready` child may then
  carry `base` and `base_pr`: the branch and URL of its one blocker's PR,
  approved at head and not merged.
- **Step 5** does not skip a child carrying `base` because its blocker is in
  flight: that blocker's merge sweep reaches the child's author when it merges.
  Dispatch it with `SKILL.md`'s recipe and its stack line.
- **In flight**: a child whose author's latest report is a merge handoff does
  not count toward the cap while `pr-verdict.sh` still reads its PR approved at
  head, so approved PRs waiting on the operator never hold a dispatch.

## The merges

On GitHub each stacked PR joins its base PR's stack
(`<skill-dir>/../git-workflow/references/stacked-branch.md`), so its handoff
carries a merge command once every PR below it is approved, and
that one merge lands them all (`git-workflow`'s `references/merge.md`, "A PR
in a stack"). A handoff for a PR with a child still to come above it is not
the operator's move: hold it. Say in a line that the PR is approved and which
PRs are approved so far, with no **Your move:** and no command, and keep the
handoff. Relay the topmost handoff as `SKILL.md`'s "Relay the merge handoff"
does, with its command as **Your move:** and the PRs it lands, once every open
child is one whose handoff you hold or one waiting only on something this run
cannot clear, such as a question only the operator answers; a held child is
finished, not still to come, though `ready-set.sh` lists it as `waiting` until
its PR merges. The operator asking to land what is approved relays the topmost
held handoff the same way, at any time. A `failed` from the
command's read-back is a merge that did not happen: pass the message to that
PR's author, whose ask comes back through you. An `enqueued` or a `pending`
is a merge still to come, which the authors' watches report.

A stack forms on a PR already approved, whose handoff may carry a `gh pr
merge` that GitHub refuses from then on. When a stacked author's PR
announcement carries `GitHub stack <n>` and the base PR's handoff carried `gh
pr merge`, `SendMessage` the base PR's author that a PR was stacked on its PR;
it sends a fresh handoff (`git-workflow`'s `references/merge-wait.md`, "A
stacked PR whose base moved"), which replaces the earlier one. A base PR whose
handoff already carried the stack's command needs no message.

When a child's PR merges, `SendMessage` the author of each open PR based on
its branch or above it in its stack: its base PR merged, so it takes
`git-workflow`'s `references/merge-wait.md`, "A stacked PR whose base moved",
resetting to the head GitHub rebased, or rebasing itself where no stack was
formed. Its fresh handoff follows its reviewer's re-verdict, and you relay it
as any other. A stacked PR that closes unmerged leaves the PRs based on its branch
without a base: `SKILL.md`'s ask on a PR closed unmerged names them.
