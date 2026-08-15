`git-workflow` and `reviewer` are held to `coding-practices`' test for when
rationale earns its line: a *why* that lets the agent choose correctly in a case
the instruction doesn't enumerate stays; a *why* that only defends an instruction
against whoever might change it moves to where that reader looks.

Most of what went was already enforceable somewhere else. `pr-verdict.sh`'s three
result fields carried a paragraph each explaining why a later simplification must
not drop them, while `tests/pr-verdict.bats` already pins every case by name and
the script's header carries the force-push reasoning. The watcher spawn had
twenty lines of comment around four lines of command, restating `bad-args`
semantics and `SETTLE` tuning that `watch-pr.sh` states at the code implementing
them.

`watch-pr.sh`'s emphasis markers drop from 19 to 10. Each remaining one names a
distinct way the watch reports the wrong thing silently — fail-open exclusion, a
self-triggering wake, a short SHA that can never match, a blind window over an
error body. The nine demoted stated a design rationale instead.
