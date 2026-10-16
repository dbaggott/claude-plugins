The issue sweep after a merge now also covers the open issues that each closed
issue blocks, so a dependent issue stops asking for work the merge already
shipped. Under `orchestrate` on a tracking issue, the author reports what its
merge shipped for each blocked sibling, and the orchestrator applies it: itself
to a child not yet dispatched, through that child's author to one in flight.
