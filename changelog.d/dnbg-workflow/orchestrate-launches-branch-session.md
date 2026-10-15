`orchestrate` now launches the fresh session a branch-loaded acceptance run needs
itself, as a background headless `claude` process, rather than handing you the
command and waiting. Your part of such a run is only the merges. When that
session exits before its merge, the orchestrator resumes it after you merge so
the run still finishes its cleanup.
