# Git workflow: a sandboxed session

Part of the `git-workflow` skill. Read this in a sandboxed Claude Code session,
before step 4's `git worktree add`.

In a sandboxed Claude Code session, three calls write the main checkout's `.git/config`, which the sandbox refuses whatever its settings: `git worktree add` from `origin/<default-branch>`, which records the upstream; the install's first run in a repository; and step 8's `git push -u`. Run those outside the sandbox. On a worktree you take over or continue, in a repository where the install has run before, the install writes nothing there and runs sandboxed. Pushes and `gh` calls also need network access to `github.com` and `api.github.com`, which the sandbox refuses unless `sandbox.network.allowedDomains` or its prompt allows them.
