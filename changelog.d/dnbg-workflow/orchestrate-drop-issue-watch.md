`orchestrate` no longer watches the issue it drives. Every event it acts on already
reached it as a subagent's report or as your answer in chat, so the watch's
wakes on review rounds, progress comments, and the author's own PR bought
nothing and brought the 40-wake restart closer. The orchestrator now waits on
its subagents alone.

One case changes for you: when an author's merge watch gives up after six hours
and the orchestrator relays the "still needs merging" reminder, tell the
orchestrator once you have merged, and it runs the author's post-merge cleanup.

`watch-issue.sh` drops its `orchestrator` role and refuses `--role=orchestrator`
with `reason=bad-args`; the `comments=` and `overflowed=` result fields went
with it.
