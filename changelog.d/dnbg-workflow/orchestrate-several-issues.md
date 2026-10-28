`orchestrate` now covers several issues with no parent in one session. Issues
each resolved by their own PR run side by side, held back while an earlier one
touching the same file is in flight. A set resolved by one PR gets one author
and one reviewer naming every issue, with decisions logged on the issue each
affects.

Retrospectives for such a set are named for its first issue, by repo and number, and list
every issue's URL in `issue:`, which `process-review` reads. An orchestrator
of several issues writes one retrospective for the session, named the same way.
