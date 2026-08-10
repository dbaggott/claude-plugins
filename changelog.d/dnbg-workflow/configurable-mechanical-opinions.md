Two of the workflow's mechanical choices are now configurable from `/plugin`,
alongside `owners`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `worktree_path` | `.worktrees` | Repo-relative directory worktrees are created in |
| `claim_label` | `assigned:agent-session` | Label an agent session applies when it claims an issue |

Set one and the session-start hook prints a short note saying so, which the
skills read as overriding the defaults they spell out; the `check-worktree` block
message names the configured directory too, so the `git worktree add` it hands
you is runnable as printed. Set neither and nothing changes — no note is printed,
and the skills' literal `.worktrees/` and `assigned:agent-session` stand.

Both values are validated, and a rejected one falls back to the default with the
reason printed at session start rather than being silently ignored. A worktree
path has to stay inside the repo (no absolute path, no `~`, no `..` segment), and
a claim label has to start with `assigned:` — the check for someone *else's*
claim matches that whole namespace, so a label outside it would make your claims
invisible to other tools and theirs invisible to you.

What stays fixed, deliberately: PRs always open as drafts, the send-to-review
picker and its option order, the `[<branch-name>]` sibling PR title tag, and
"only a human merges".
