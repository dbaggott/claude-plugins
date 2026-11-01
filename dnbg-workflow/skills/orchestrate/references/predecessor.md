# Orchestrate: a predecessor, or an agent that died

Part of the `orchestrate` skill. Read this when an agent's task ends `failed`
on an API or usage limit error, and before dispatching an author with any of
the dispatch recipe's predecessor lines: an open PR that step 3 found or the
operator handed over, a worktree step 3 found, or a dead author to replace.
The recipe and its other lines are in `SKILL.md`'s "Dispatch the author, then
the reviewer".

## Which predecessor lines go in

The `Continue <PR URL>` line goes in only for an open PR that step 3 found as
`closes` or `sibling`, that the operator handed over, or that a dead author
left; the worktree line only for a worktree that step 3 found or a dead author
left; and the died-mid-task line only when replacing a dead author, with each of
its parts that applies.

## An agent died on an error

**An agent died on an error** when its task ends `failed` on an API or usage
limit error rather than with a report. Resume it with `SendMessage`, telling it
to carry on from where it stopped, since its context survives: after a usage
limit, once the reset time the error names has passed; after any other API
error, after a few minutes. Wait on a background `sleep`
with `timeout: 7200000`, and when it returns before the reset time, sleep
again rather than resume. If it fails the same way again, ask the
operator. Dispatch a fresh agent in its role only when `SendMessage` cannot
reach it. For an author, fill the recipe's predecessor lines from the dead
one's state: its worktree and unpushed commits (`git -C <worktree> log HEAD
--not --remotes`), which `pr-sources.sh` cannot see, the review round it was
answering, and any scratch issues or labels it created. A replaced agent leaves
no close-out: "Asking the agents for one" in
`<skill-dir>/../process-review/references/retrospective.md` says what the Stop
report does about it.
