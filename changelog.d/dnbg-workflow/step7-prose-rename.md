`git-workflow`'s self-review now skips the code-review tool for a diff that is
only prose no agent executes (a README, a changelog entry) or only a rename the
issue fully specifies, as it already did for data-only diffs. Skills, rules files
and `CLAUDE.md` still count as logic and still get the full review. The PR says
when the review was skipped and why.
