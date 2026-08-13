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
