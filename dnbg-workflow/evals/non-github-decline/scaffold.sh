#!/usr/bin/env bash
# A one-commit repository whose origin was never fetched: the run has no
# network, so refs/remotes/origin/main is made here for a worktree to branch
# from. HOME is the run's own, so the identity is set in the repository.
set -euo pipefail
git init -q -b main
git config user.name 'Eval Run'
git config user.email 'eval@example.com'
printf '.worktrees/\n' > .gitignore
printf '# widgets\n\nA libary of reusable widgets.\n' > README.md
git add .gitignore README.md
git commit -q -m 'Initial commit'
git remote add origin https://gitlab.com/acme/api.git
git update-ref refs/remotes/origin/main HEAD
