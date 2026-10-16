`git-workflow`'s self-review now skips the code-review tool for a diff made only
of prose no agent follows as instructions (a user-facing README, a changelog
entry), or only of a rename the issue fully specifies, as it already did for
data-only diffs. Prose that instructs an agent, such as a skill or a `CLAUDE.md`,
still counts as logic and still gets the full review. The PR says when the
review was skipped and why.
