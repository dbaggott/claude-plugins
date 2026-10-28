When `git-workflow`'s worktree setup cannot write the git config that points a
worktree's pushes at the author role, its error now names the file it could not
write and says a sandbox is the likely cause. In a Claude Code sandboxed
session, the main checkout's `.git/config` is never writable, so that call has
to run outside the sandbox.
