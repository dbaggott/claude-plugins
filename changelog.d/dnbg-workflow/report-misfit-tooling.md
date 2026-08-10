New always-on rule: when a script, hook, or procedure the plugin ships doesn't
cover your case, the agent finishes the task the narrow way, then tells you what
didn't fit and offers to report it upstream.

Filing is never agent-initiated. An issue against this project is published
under *your* GitHub identity to a repo you don't control, so it happens only if
you ask for it, is written from the generic case with nothing personal or
session-specific in it, and is shown to you in full for approval before it is
submitted. With no user present to ask, nothing is filed.

The rule also states two things that were previously implicit: a hook that
blocks you is working as intended and should be satisfied rather than routed
around, and the installed plugin copy under `~/.claude/plugins/` is never a
place to edit — those edits are unreviewed and are destroyed by the next update.
