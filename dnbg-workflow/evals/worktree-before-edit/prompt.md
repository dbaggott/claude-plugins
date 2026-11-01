---
description: Whether an edit in a covered repo starts in a worktree. The prompt gives the premise the agent cannot read, that the repo is covered, and measures whether the always-on rule's consequence follows.
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit]
---

`README.md` in this repository misspells "library" as "libary". Fix the typo and commit the fix. Stop after the commit: don't push and don't open a pull request.

Two facts about this environment. `acme`, the owner of this repository's `origin`, is one of the accounts the dnbg-workflow plugin's `owners` setting covers. And there is no network, so any `git fetch` or `gh` call fails: work past such a failure rather than stopping on it.
