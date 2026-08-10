The workflow skills now state that they are GitHub-only and decline cleanly on
another forge, instead of running `gh` commands that cannot work and surfacing a
cascade of confusing errors.

`git-workflow` and `issue-workflow` read `git remote get-url origin` before they
act, and on a non-`github.com` host they say so, name the host they found, and
hand back to whatever flow your project already uses — they do not attempt a
`gh` call and do not translate themselves to another forge's CLI. A repo with no
`origin` is not treated as a decline: it makes no forge claim either way, so
they proceed rather than guessing a host.

`reviewer` judges the repo holding the PR you named, not your working directory,
and `reviewer-setup` is not repo-scoped at all — both keep working when you
review a GitHub PR from a checkout of some other forge's repo.

`velocity-tradeoff` is unaffected on every host. It ships in this plugin but
mentions no forge, and declining is decided per skill rather than per plugin.

The README now carries a support matrix naming every forge — GitHub supported,
GitLab and Bitbucket planned, Azure Repos not planned, everything else including
self-hosted and GitHub Enterprise unsupported — and states which plugin ships
each skill and whether that skill needs a forge at all.
