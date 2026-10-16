The PR watch's `result=CHECKS` now names the failing tests, as
`failed_tests='<names>'`, when the failed job's log carries TAP `not ok` lines,
so an author no longer digs them out of the log by hand.

`git-workflow` now says what to do when a check fails in a test the diff doesn't
touch: rerun the failed jobs once and wait on the rerun. A pass is a flake to
report, not a change to the PR; a second failure on the same head is
investigated as a finding.
