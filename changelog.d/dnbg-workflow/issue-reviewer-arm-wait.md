Fixed spec reviews stopping after their first round. `issue-reviewer` now arms
the wait for the author's response as the last step of posting every round that
did not converge or halt, so a `CHANGES REQUESTED` round is followed up when the
author answers instead of going unread.
