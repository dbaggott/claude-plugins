`reviewer` now applies a bar to non-blocking observations before they go in a
review body. Previously the only test was "does this block the merge", so a
correct-but-minor note went in unchallenged — and each one an author acted on
moved HEAD, which correctly costs a fresh verdict, a fresh CI run, and often a
fresh round of notes about the fix. Five tests now gate the body: could acting on
it change a tracked file; did this diff change the line or make it wrong; does
your own phrasing ("defensible", "reasonable either way") already argue it down;
could you be wrong in a way only the author can check, from session state a
reviewer never sees; and, on a re-review, would it have been worth raising in
round 1. Reviews now hand the pacing decision over as a sentence — "none of this
needs a round before merge" — rather than a section headed "Non-blocking".

None of this reduces what a reviewer checks. Every test bars a *finding from
being published*; none bars a *check from being run*.

Two rules moved to where they bind. The ban on padding a review with CI status
now sits with the body-composition instructions rather than in the CI step, and
says that a check result changing the verdict is a finding while one that does
not belongs only on the PR page, where it is live rather than a stale snapshot.
The anti-filler rule now covers re-verdict bodies as well as thread replies: a
re-verdict states the SHA, the verdict, and what changed, without ratifying the
author's reasoning back at them. Verification is reported selectively — narrated
on `APPROVE` where it justifies the verdict, compressed to a list of surfaces
checked on `REQUEST_CHANGES`.
