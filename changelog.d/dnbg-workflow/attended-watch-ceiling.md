In an attended Claude Code session (terminal, desktop app, VS Code), a watch now
serves its whole six-hour window in one run instead of ending every 105 minutes
with an `IDLE window_left=` result to re-arm from. Those sessions put no time
limit on background commands, so the split only cost a wake. Unattended sessions
(`-p`, the Agent SDK, CI, cloud) keep the 105-minute ceiling, as does any session
that does not set `CLAUDE_CODE_SESSION_ATTENDED=1`, and an explicit
`WINDOW_CEILING` still wins in both.
