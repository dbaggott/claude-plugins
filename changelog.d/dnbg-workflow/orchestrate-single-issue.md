New `orchestrate` skill: say "orchestrate the resolution of <issue URL>" and the
session claims the issue, dispatches an author and a reviewer as subagents, and
drives them to a merged PR. It answers the author's questions that the issue's
own body settles, brings you the rest, and records every answer on the issue as
a `Decision log:` comment. A restarted orchestrator picks up from the issue
alone, after asking you to confirm its predecessor is gone. Tracking issues with
sub-issues are not orchestrated yet.

Claiming an issue, and checking whether it is already someone else's, is now one
script call in `issue-workflow` rather than several hand-typed commands. The
claim marks themselves are unchanged.
