An acceptance criterion met by a recorded run, such as an eval, no longer has
to be run before the PR leaves draft when review fixes would likely void it.
When the run's paths overlap the skill text the PR changes, the author can mark
it pending in the PR description and make it after the first review round with
no blocking finding, so a single run usually suffices.

`reviewer` grades that pending run, and a re-run already in progress, as a
conditional approval rather than a blocking finding, and re-verdicts on the
run's record when it lands. When its own findings will void a run, it asks for
the run after the fixes instead of grading the current one. Neither the author
nor `orchestrate` hands the PR off for merge until the re-verdict on a pending
run is in, and `orchestrate` asks the operator for their part of a deferred run
only once the conditional approval is in.
