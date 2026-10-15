Fixed a first watch that could never fire. Every skill armed its first issue or
PR watch from the clock, so a reply, verdict or comment posted while the agent was
still finishing its own step fell before the watch's start and was never seen. The
agent then waited out the whole window. A first watch now starts from the time of
the agent's own last action, and when another party may already have acted, the
skills say to read the issue before waiting on it.

The issue watch has two new options. One picks which events wake it: comments,
linked PRs, body edits or closing. The other names further logins to ignore. The
existing roles behave as before. Every result the watch can be re-armed from now
also carries the next run's settings as fields, so a script can continue a watch
without parsing the printed command.
