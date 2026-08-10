The always-on rules now reach subagents, not just the main conversation.

`SessionStart` output — which is how this plugin injected its rules — reaches the
main loop and nothing else, so any subagent you spawned had never been told to
work in a worktree, to reference issues by full URL, or about any configuration
override you had set. A new `SubagentStart` hook injects the same rules into each
subagent.

This is a behavior change on an installed machine: subagents now see the rules
and act on them, and each spawn costs the tokens the rules occupy.
