`orchestrate` now drives a tracking issue, not only a single issue. Point it at a
tracking issue and it works through the sub-issues in dependency order, up to
three at a time. It claims each one before dispatching an author and a reviewer
to it. A sub-issue waits while a blocker is open, while someone else holds it,
or, in a project that uses spec review, until its latest review reads READY.

Answers and escalations are logged in the parent's decision-log table as well as
on the child. A decision that changes the design is applied right away: the
orchestrator edits the parent, updates the children that cite what changed,
re-runs their spec review, and tells any agent working on them. It flags
problems that span several children, such as two questions about the same
requirement or the same review finding on two PRs. When every child is closed,
it hands the project to the reviewer's whole-project review and stops on that
verdict.
