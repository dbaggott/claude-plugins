`orchestrate` now restarts on the size of its context rather than on a count of
its wakes. An attended orchestrator reads its context size at each wake and
hands over to a fresh session at 150K tokens, at the first compaction, or, when
the size cannot be read, after 20 wakes; before, it waited for 40 wakes, which
almost no run reached. Once a restart is due it starts no new work and waits for
the authors already running to open their PRs. Each wake of a long run re-sends
less, since the context it re-sends stays smaller.

A headless orchestrator, with no one there to start its successor, keeps the old
triggers: 40 wakes or the first compaction.
