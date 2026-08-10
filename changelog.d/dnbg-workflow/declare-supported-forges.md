The workflow skills now state that they are GitHub-only and decline cleanly on
another forge, instead of running `gh` commands that cannot work and surfacing a
cascade of confusing errors.

`git-workflow` reads `git remote get-url origin` before it acts, and on a
non-`github.com` host it says so, names the host it found, and hands back to
whatever flow your project already uses — it does not attempt a `gh` call and
does not translate itself to another forge's CLI. A repo with no `origin` is not
treated as a decline: it makes no forge claim either way, so the flow proceeds
rather than guessing a host.

`issue-workflow` resolves the host from the issue itself. An issue named by full
URL carries its own host, and that is what decides — the working directory is
not consulted at all, so picking up a GitHub issue from a GitLab checkout works
normally. Only a bare issue number, or creating an issue in place, falls back to
reading `origin`; the no-`origin` behavior above applies on that route.

`reviewer` judges the repo holding the PR you named, not your working directory,
and `reviewer-setup` is not repo-scoped at all — both keep working when you
review a GitHub PR from a checkout of some other forge's repo.

`velocity-tradeoff` is unaffected on every host. It ships in this plugin but
mentions no forge, and declining is decided per skill rather than per plugin.

The README now carries a support matrix naming every forge — GitHub supported,
GitLab and Bitbucket planned, Azure Repos not planned, everything else including
self-hosted and GitHub Enterprise unsupported — and states which plugin ships
each skill and whether that skill needs a forge at all.
