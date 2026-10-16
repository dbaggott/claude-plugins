A design review of a tracking issue now re-runs each constraint's verification
method when it is a single read-only command the reviewer can run, such as a
`gh api` read, a `--help` or a grep of the tree, and blocks on a constraint whose
result does not match its claim. A method that is an experiment, needs
credentials or has side effects is still only checked for being named.
