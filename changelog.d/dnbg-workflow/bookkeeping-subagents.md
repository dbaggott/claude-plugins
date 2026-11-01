Under a tracking issue, the orchestrator now runs its larger bookkeeping reads
in short-lived subagents that reply in a line or two, so those reads no longer
sit in its context through every later wake: collecting decision rows from more
than three children, a merge's sweep of more than one sibling, and the scan for
review findings that recur across children's PRs, which now reads each PR's
inline review comments with their file paths. The orchestrator still makes
every decision, escalation and message to an author.
