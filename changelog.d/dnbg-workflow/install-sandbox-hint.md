`git-workflow`'s worktree setup now works in a Claude Code sandboxed session
for every worktree after a repository's first. Only that first setup has to
run outside the sandbox, because it writes the main checkout's `.git/config`,
which the sandbox never allows. When a setup does fail to write its git config,
the error now names the file and says a sandbox is the likely cause.

Pushes and `gh` calls from a sandboxed session also need `github.com` and
`api.github.com` allowed for network access; `git-workflow` step 4 says so.
