`watch-pr.sh` now hands the round over instead of half-delivering it.

On the results with a round behind them (`ACTIVITY`, `COMMITS`, `READY`) it
prints a `── next ──` line carrying the `pr-round.sh` call with every argument
already filled in — it holds that whole tuple anyway. And it no longer prints
comment bodies: the activity lines say who posted what kind of thing and where,
and `pr-round.sh` delivers the text, the unresolved threads and the diff
together.

Bodies in the wake made it read as a complete round while carrying neither the
threads nor the diff, so a caller could act on it and be wrong — and a caller who
ran `pr-round.sh` anyway paid for every body twice.

`reviewer` gains a step telling it to run that printed command; `pr-round.sh` was
previously reachable only from `references/re-review.md`, two hops from the
skill, so a round got assembled by hand instead. Its batching rule also gains a
carve-out: a read that decides *how* to do the reads beside it cannot ride along
with them, or it arrives after the work it governs.

`git-workflow` now distinguishes the two reply ids. An inline object's `id` is
the REST comment id that `in_reply_to` takes; the GraphQL mutation it documents
takes the `PRRT_…` thread id from the round packet's threads section, and the
prose previously implied they were the same.
