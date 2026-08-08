The `reviewer` skill now spends its budget where findings actually come from.

Behavior changes, effective as soon as the plugin updates:

- **The reviewer no longer re-runs the project's test suite.** A local run
  reproduces the author's environment rather than CI's, so on a timing- or
  load-sensitive defect it argues "flaky, ignore it" — the wrong verdict. CI
  verifies and enforces green; the reviewer reads the check results instead.
- **Instrumented reproduction of one doubted claim is still permitted**, and is
  explicitly triggered by doubt about a specific claim rather than by a red
  check — the most valuable probes tend to run while CI is green.
- **The reviewer never waits for or polls CI.** It reads whatever check state
  exists when it looks, once, and proceeds.
- **It reads less of each file**: diff hunks for a `MODIFIED` file, and no
  re-fetch of an `ADDED` one (the diff already carries it), fetching whole files
  only when the hunks don't carry enough context.
- **Re-reviews read `compare/<last-reviewed-sha>...<new-head>`** rather than the
  full PR diff again — cheaper, and exactly the changes the prior verdict didn't
  cover.

Judging test coverage by *reading* tests is unchanged; the restriction is
narrowly about executing them.
