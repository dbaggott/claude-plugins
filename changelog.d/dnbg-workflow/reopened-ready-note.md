In an issue-set review, when a fix for one issue's finding edits another issue
that was already `READY`, `issue-workflow` now gives the note the author posts
there: the finding that caused the edit, the section that changed, and
`No blocking findings were open here.` The author posts it before the response
on the finding's own issue and watches the edited issue too. `issue-reviewer`
treats any edit to a `READY` issue as a new round to verdict.
