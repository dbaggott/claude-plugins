`orchestrate` no longer watches the PR. It dispatches the reviewer when the
author ends its turn with the PR URL, and treats the author's final report as
the merge signal, so a run wakes less often. When the review is clean, the
author ends its turn with its merge handoff and the orchestrator relays it
as written: the command in a fenced block, the author's report beneath, plus
the reviewer's verdict and SHA. It no longer rewrites the command or holds it
until checks finish.

The orchestrator also stops checking the issue against the tree before
dispatch, since the author's pickup review does that, and stops editing an
issue body once an author is working on it: it sends the answer and the author
writes it into the body. The scheduled hand-over to a fresh session after 40
wakes now applies to single-issue runs too.
