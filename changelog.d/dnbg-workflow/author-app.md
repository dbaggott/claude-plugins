The author is now a role with its own GitHub App. Once you create it with
`reviewer-setup` (`--roles author`, or alongside the others), the author's
PRs, pushes, comments, thread replies, claims and filed issues post as the
author bot, so you can approve its PRs yourself, and your own comments on its
PRs and issues wake it. Commits stay authored by you. Without an author App,
everything posts as you, as before, and the session-start notice says so.

Pushes go through a credential helper that `git-workflow` installs in each
worktree's own git config, minting a fresh token per push; the main checkout is
untouched. A worktree with an SSH `origin` now pushes over HTTPS, through that
helper. With no author App, that means `gh`'s token rather than your SSH key,
which needs the `workflow` scope to push workflow files (`gh auth status`).
