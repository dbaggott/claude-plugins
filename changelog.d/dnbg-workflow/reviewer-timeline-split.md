Split `reviewer`'s `SKILL.md` along the review timeline rather than by topic. The
file now carries the path a first pass actually walks — identify the PR, get a
token, do the work, post, spawn the watch — and hands off to three new reference
files at the point each one binds: `references/watch.md` on the watcher's first
return, `references/re-review.md` when HEAD moves, and `references/worktree.md`
on the minority of reviews that need a checkout. Each is pointed at from the step
that precedes needing it, so nothing has to be found from a reference list. The
skill drops from 860 to 633 lines.

The motivation is placement as much as size: several rules were correct but sat
in a section the reviewer was not in when they applied.

**Loading the coding standards is now step 1 of the review**, ahead of reading
the diff, and it says whose standards apply — the PR's repo decides, not your
working directory, which for a reviewer working remotely is not the same thing.
Previously the flow began at "read the diff" and only mentioned the standards in
passing four steps later, phrased as though they were already loaded; a reviewer
that had not loaded them met nothing that said to. In the issue-scoped mode the
load belongs in the wait for PRs to appear, which is where `references/issue-mode.md`
now puts it.
