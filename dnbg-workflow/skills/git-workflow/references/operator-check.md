# Git workflow: operator check before review

Part of the `git-workflow` skill. Read this when the issue you are resolving
has a `## Operator check before review` section, unless your prompt says the
check has cleared, before step 7's self-review. The steps it names are
`SKILL.md`'s.

An issue can reserve a look at the work for the operator before it is polished
and reviewed, in a `## Operator check before review` section carrying the recipe
for bringing the work up and what to look at (`issue-workflow`'s
`references/creating.md`). The stop comes when the work is complete, at the point
step 7 would otherwise start; an open draft PR is its precondition, not its
trigger. With the check declared, the order is: commit, push, open the draft PR
(already open for an orchestrated author), the check, the self-review (step 7),
a push of its fixes, then steps 9 and 10; step 8 has already run.

1. Start the recipe as a background task in the worktree. A server never exits,
   so its task never wakes you: start a second background task that exits once
   the first's output file carries the line naming how to reach it, bounded,
   such as `for i in $(seq 1 120); do grep -q 'port' <output file> && exit 0;
   sleep 0.5; done; exit 1`. When it exits non-zero the recipe did not come
   up: read the recipe task's output and ask about that, in place of the URL
   below. Read the port from the announced line rather than from the recipe:
   several worktrees can be serving at once, so the port asked for is not
   necessarily the one got.
2. Announce the PR URL, what to look at, and how to reach it. Then call
   `AskUserQuestion` with two options (the tool auto-appends "Other", which
   carries the feedback):
   1. **"Proceed"** — "Stop the server and go on to the self-review."
   2. **"Changes needed"** — "Say what to change; the work comes back for
      another look."
3. On "Changes needed", rework, commit, push, restart the recipe unless it
   reloads on its own (stop the task by its id, start it again, re-read the
   port), and ask again. On "Proceed", stop the server task by its id and
   continue to step 7.

Without `AskUserQuestion`, post the same as a `Delegated question:` and end the
turn with it, per `<skill-dir>/../issue-workflow/references/delegated.md`,
leaving the server running: its URL has to be reachable when the answer
arrives.
