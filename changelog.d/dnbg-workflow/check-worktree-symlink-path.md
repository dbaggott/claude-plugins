The `check-worktree` hook's block message now names the file and the retry path
correctly when the edited path reaches the repo through a symlink — on macOS,
anything under `/tmp`, and any symlinked home or project directory. Previously
both stayed absolute, so the retry path the message told you to use was the
worktree root joined to a second absolute path, a location that could not exist.

The gate itself is unchanged: a tracked file in a main checkout was blocked
before and still is. Only the text you act on after the block was wrong.
