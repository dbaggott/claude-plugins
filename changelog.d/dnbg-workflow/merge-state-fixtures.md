The merge-state mapping is now checked against GitHub's own schema rather than
against cases somebody thought of, and `HAS_HOOKS` is fixed.

`tests/fixtures/capture-enums.sh` pins the `MergeStateStatus` and
`PullRequestReviewDecision` enums from GraphQL introspection, and a test asserts
every documented value maps to something a caller acts on. That guard fails on
the mapping as previously shipped: **`HAS_HOOKS` is a mergeable state** — GitHub
documents it as "mergeable with passing commit status and pre-receive hooks" —
and it was read as an unrecognised one, so on any repo with pre-receive hooks a
mergeable PR looked like a state no caller acts on.

One status is now three, because they were three different questions wearing one
answer:

- `clean` also covers `HAS_HOOKS` — mergeable, with a `cause` saying why it was
  not plain `CLEAN`.
- `indeterminate` is GitHub's `UNKNOWN`, documented as "the state cannot
  currently be determined". It means ask again, and GitHub returns it routinely
  while mergeability is recomputed.
- `unrecognised` is a value GitHub has never documented — the schema moved, and
  the remedy is a person re-running the capture script rather than another poll.
  An author-role watch surfaces it on its window's `IDLE` rather than acting on
  it; merge state is not a reviewer's business, so that role reports none of it.

`tests/fixtures/capture-pr-state.sh` records real `gh pr view` payloads, each
carrying the repo, PR and branch protection it came from, and
`tests/merge-cause.bats` replays them. These hold combinations no hand-written
payload establishes — which `mergeStateStatus` GitHub pairs with which
`reviewDecision` under which protection — and that is the shape every defect this
mapping shipped with took.
