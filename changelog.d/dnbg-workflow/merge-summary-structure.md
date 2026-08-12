Two changes to what the skills do around the end of a review cycle.

`reviewer`'s draft picker now recommends **waiting**. Naming a draft PR for
review still asks before reviewing it, but the options are reversed: "Wait until
it's ready" is the recommended first option and the one an unattended run takes,
and "Review it now" is second. Draft is the author's signal that the work is not
yet endorsed for review, which is already why a draft the reviewer *discovers*
is held back without asking at all.

`git-workflow` and `reviewer` now report the finished cycle under three
headings — **Summary** (what happened), **Observations** (informational, nothing
to do), **Actionable** (things the operator may want to act on, each naming a
concrete next step). All three appear every time, with "None" under an empty
one, and an item that could go under either lands in Actionable. Neither skill
acts on its own Actionable list: filing and fixing stay the operator's call.
