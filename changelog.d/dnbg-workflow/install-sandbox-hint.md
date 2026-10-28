In a Claude Code sandboxed session, setting up pushes on a worktree you take
over or continue now works sandboxed, once that setup has run in the repository
before. A failed setup's error now names the file it could not write, gives
git's own reason, and says a sandbox is the likely cause.

`git-workflow` step 4 now lists what a sandboxed session must run outside the
sandbox: creating a worktree, the first setup in a repository, and the first
push, since each writes the main checkout's `.git/config`, which the sandbox
never allows. Pushes and `gh` calls also need `github.com` and
`api.github.com` allowed for network access.
