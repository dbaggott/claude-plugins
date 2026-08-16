Reviews from the `reviewer` bot were not counting. GitHub does not let a review
from an App that lacks write access to repository contents affect a pull
request's approval state — so on a repo that requires an approval the bot could
never satisfy it, and threads it opened could not be resolved. The review
appeared on the PR, read correctly, and did nothing. It asks for that access
now, and `reviewer-setup` grants it when it creates an App.

Setting up a reviewer also checks what the App was actually granted, and says
what is missing and how to fix it if anything is. An App holding extra
permissions for other purposes is fine.

## Migration

**An App created before this release keeps its old permissions.** GitHub fixes
them when the App is created, so re-running the setup will not change one. Add
*Contents: Read and write* under your App's permissions, then accept the pending
request on each installation — the grant does nothing until you do.
`reviewer-setup`'s **Repair / rotate** section has the steps. If you skip this,
the reviewer will tell you the next time it runs.
