With retrospectives on, each role's retrospective now records what its run
cost: the new `session-usage.sh` finds the agent's own transcript and reports
its request count and token counts (input, cache writes, cache reads, output)
in the retrospective's frontmatter. A session's owner also gets one line per
agent it dispatched, and posts the session's figures on the issue as a comment
starting `Usage:`, so a run split across restarts can be added up from the
issue. The orchestrator now writes a retrospective when it restarts, not only
when it stops.

Retrospectives gain a fifth heading, **Read but not used**, for reference files
an agent read and did not need.
