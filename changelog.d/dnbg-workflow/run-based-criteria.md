An acceptance criterion met by a run, such as an eval or a live exercise, now
names the paths whose change invalidates the run, so a later commit outside them
no longer means running it again. Authors run such criteria before sending the
PR to review and ask early for any part the operator must do. Reviewers grade
the recorded run against those paths, and approve conditionally, with an
observation, when the only thing left is an operator action outside the PR.

When a tracking issue is decomposed, each end-to-end criterion met by a run
names who records it. The orchestrator runs any criterion that only a main
session can run, and the author records it. A reviewer watching an issue no
longer reports the same merge twice.
