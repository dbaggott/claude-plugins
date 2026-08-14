A force-push can move a standing review onto the rewritten commit, so the
"is HEAD approved?" check reported an approval for a tree nobody had reviewed.
`pr-verdict.sh` and `pr-round.sh` now also report `reviewed_after_head`, from
the verdict's submission time against when the commit at HEAD was created, and
both `git-workflow` and `reviewer` require it alongside `at_head`.

Expect one extra review round after a rebase, including a rebase that only
inherits already-reviewed content. The reviewer re-verdicts unprompted on any
HEAD move, so the fresh verdict arrives on its own.
