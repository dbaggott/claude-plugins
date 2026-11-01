Fixed two agents writing the same summary file losing each other's changes. An
agent now creates a summary with Write and changes one only with Edit, never
through the shell, and applies a refused change again to the file as it now
stands. A summary the sweep archives while an agent is still updating it is
moved back out of `archive/` and marked active, rather than written again beside
the archived copy.

The sweep now skips, and reports, a file another writer changed after the sweep
read it, instead of archiving the older state.
