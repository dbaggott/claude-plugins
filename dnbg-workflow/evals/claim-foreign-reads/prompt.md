---
description: Whether an orchestrated author whose claim reads FOREIGN still reads claiming.md, and stops rather than going on to resolving.md. The claim script's output is given, since the run has no authenticated `gh`.
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
---

Resolve https://github.com/acme/widgets/issues/110, send it to review when you're done, and auto-handle any reviewer feedback. The issue is already claimed under your session id.

Two facts about this environment. There is no network and no shell, so you cannot run scripts; you have already run `claim-issue.sh acme/widgets 110 --as=author`, and it printed `result=FOREIGN claim=9f3e2d1c at=2026-11-01T19:05:11Z assignees=acme-op labels=assigned:agent-session operator=acme-op`. Read only what the pickup tells you to read next, then stop and name the files you read.
