The reviewer bot now needs `contents: write`, and acts under its own credentials
throughout.

Two things an App cannot do without that permission, both established against a
live PR rather than reasoned about:

- **Resolve its own review threads.** `resolveReviewThread` answers
  `FORBIDDEN: Resource not accessible by integration` to an App token that lacks
  it. `pr-threads.sh --resolve` used to sidestep this by clearing `GH_TOKEN` and
  running under the operator's auth; it no longer clears it, so the reviewer
  resolves as itself.
- **Have its verdict counted at all.** GitHub leaves a review by an App without
  `contents: write` out of `latestOpinionatedReviews`, so `reviewDecision` never
  moves. The review shows on the PR page and the merge box ignores it — on a repo
  requiring an approval, nothing the bot posts can satisfy the gate. Granting the
  permission counted the *existing* review retroactively, which is how the
  mechanism was confirmed: `authorAssociation` stays `NONE` throughout and the
  installation still reports `push: false`, so neither of those is the signal.

`reviewer/SKILL.md` claimed a bot verdict is what satisfies a required review. It
is — but only with this permission, which the setup script did not grant. Both
halves are now true together.

The write is broader than the need: it also permits pushing source. GitHub offers
no narrower grant for either capability, so the scoping lever is the
installation's repository list rather than the permission.

**An App created before this change keeps the old permission set** — a manifest
is read once, at creation. `reviewer-setup`'s verify step compares each
installation against `bootstrap.py` and now flags it; its **Repair / rotate**
section covers editing the App and accepting the change per installation.
