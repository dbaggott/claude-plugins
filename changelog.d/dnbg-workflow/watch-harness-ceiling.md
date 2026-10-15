PR, merge and issue watches no longer get stopped silently in headless
`claude -p` sessions. Those sessions stop a background command after 10 minutes
unless it was given a longer Bash `timeout`, and a watch stopped that way prints
no result. Every skill now spawns its watches with `timeout: 7200000`, the
longest the harness allows. A watch window longer than about 105 minutes, such
as the six-hour merge wait, now runs as several shorter runs: each run returns
`IDLE` with `window_left=<seconds>`, and its re-arm line carries the rest of the
window.
