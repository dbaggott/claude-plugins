`reviewer` now spends fewer calls per review. It previously budgeted only bytes,
so a reviewer could read economically and still burn a cycle on round trips: the
round trip is now named as a cost alongside bytes, independent probes go in one
call rather than a sequence, and a check needing the same field across many PRs
or issues is one GraphQL query instead of a `gh` loop per item. The per-call bot
token mint is explicitly exempted — it is an extra API call, not an extra round
trip, and collapsing those blocks posts the review under the wrong identity.

Reading the tree gained a middle mode. Between per-file `contents` fetches and a
full worktree there is now a tarball fetched into a scratch directory: past ~2
questions of the tree, or for any repo-wide sweep, one call gets the whole tree
and leaves nothing in the repo to clean up. The worktree triggers narrowed to
match — a probe that *runs* something still needs a checkout, a probe that only
reads gets its files fetched.

Three smaller additions: whole-file fetches are filtered at the pipe rather than
landing in context; `gh pr diff`'s lack of pathspec support is stated with the
per-file-patch idiom that replaces it; and the review-comments fetch is skipped
when no inline threads were filed, since it can only answer empty.

Between watch cycles, a reviewer now reports a status line rather than restating
the review. The review body is the artifact, and the full three-section report is
owed once, when the PR closes.

None of this changes what a reviewer checks or concludes.
