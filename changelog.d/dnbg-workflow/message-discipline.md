`git-workflow` now says to claim less in a PR description, not only to claim
accurately. The existing bar — every claim true and earned — pushes toward
checkable detail, and every checkable detail is something a reviewer will verify
whether or not it was worth stating. The test is what a reviewer does differently
for having it: a number that scopes the diff earns its place, a number that only
describes the work does not.

It also names the terminal fix. Where a finding's whole remedy is editing prose
that ships — a description, a commit message, a changelog fragment — and nobody
acts on the detail, cut the claim rather than correcting it; correcting keeps the
liability for the next time it drifts. `issue-workflow` already points here for
issue bodies, so they inherit both.

`reviewer` gains the matching half: raise a message-only finding as "cut it"
rather than "correct it", since only one of those ends the exchange.
