`git-workflow`'s merge wait now says how to arm the merge-stage watch when there
is no `── re-arm ──` line to edit, because the review watch died without a result
or the PR was taken over from another author. The head, the verdict SHA and
`since` all come from one `pr-verdict.sh` call, which now also prints
`verdict_at=`, the time the standing verdict was submitted.
