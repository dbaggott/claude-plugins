Fixed the issue watch silently ignoring a PR to exclude when it was given as a
number (`286` or `#286`) rather than its full URL. The watch then woke on that
PR anyway. It now refuses to start, saying its arguments were bad, and
`orchestrate` treats that refusal as its own command to fix and re-run rather
than an authentication problem.
