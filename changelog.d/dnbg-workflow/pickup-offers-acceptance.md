Picking up a tracking issue that has no children and no acceptance row now asks
the acceptance question when its latest design-mode review is still `READY`
against the body as it stands, instead of starting another review. This covers
an earlier "Not yet" answer and a session that ended before asking. A stale or
non-design-mode `READY` still leads to a review.

`project-status` agrees: `issue-stage.sh` now says `next=accept` only for a
current design-mode `READY`, and adds a `round=current|stale|not-design`
evidence key beside it. `ready-set.sh`'s parent object gains `verdict_mode` and
`verdict_against`, and `issue-reviewer` now states the form its round comments
use for the `lastEditedAt` they were reviewed against.
