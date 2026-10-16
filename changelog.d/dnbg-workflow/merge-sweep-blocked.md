The issue sweep after a merge now also covers the open issues that each closed
issue blocks, so a dependent issue stops asking for work the merge already
shipped. A swept issue someone else has claimed gets a comment naming what
shipped instead of an edit to its body.

Under `orchestrate` on a tracking issue, the author reports what its merge
shipped for each sibling, and the orchestrator applies it: itself to a child no
one holds, through the child's author to one in flight, and as a comment to one
held outside the run. The orchestrator also holds a ready child's dispatch
while any of its blockers is still in flight, so that sweep lands before the
child's author reads its body.
