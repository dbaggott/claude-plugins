---
type: tool_order
before: { tool: Bash, input_match: '\bworktree\s+add\b' }
after: { tool: Edit, input_match: '/\.worktrees/' }
---

Matches `worktree add` rather than `git worktree add`: where the sandbox cannot run `/usr/bin/git`, runs call another git through a variable or a full path, as in `$G worktree add`.
