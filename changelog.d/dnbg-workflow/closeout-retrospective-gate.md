The close-out sites across `git-workflow`, `reviewer`, `issue-reviewer`,
`issue-workflow` and `orchestrate` now route through `process-review`'s
"When a retrospective is written" instead of naming a retrospective file, its
path or a Retrospective section. With retrospectives off (the default), an agent
following its close-out line no longer writes a file the setting forbids, and a
dispatcher no longer asks a subagent for a path that does not exist.
