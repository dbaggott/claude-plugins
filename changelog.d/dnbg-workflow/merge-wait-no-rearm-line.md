`git-workflow`'s merge wait now says how to arm the merge-stage watch when there
is no `── re-arm ──` line to edit, because the review watch died without a result
or the PR was taken over from another author: read the approved head and verdict
with `pr-verdict.sh`, take `since` from the approval's `submittedAt`, and add
`WINDOW=21600 --merge-stage`.
