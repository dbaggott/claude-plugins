---
name: Documentation
about: The README, a skill body, or another doc is wrong, missing, or unclear
title: ''
labels: documentation
assignees: ''
---

<!--
This issue will most likely be picked up cold — by a fresh agent session, or by
someone who has not read this thread. Everything a resolver needs should be
readable here without clicking through. See CONTRIBUTING.md for the reasoning.

Note that a skill body is not "just docs" — it is the instruction a model acts
on, so a wrong sentence there changes behavior. If that is what this is about,
say so; it changes how the change gets reviewed and whether it needs a changelog
fragment.

Delete any section that genuinely does not apply, rather than leaving it empty.
-->

## Problem

<!--
Which document, which passage, and what is wrong with it — missing, inaccurate,
ambiguous, or contradicted by observed behavior. Quote the passage rather than
only citing its location; line numbers move.

If the doc contradicts what the code actually does, say which one you believe is
correct and on what evidence. That decides whether this is a doc fix or a bug.
-->

## Proposed approach

<!--
What the text should say instead. A concrete replacement is worth far more than
a description of one.

VERIFY EACH ANCHOR against the current tree before filing, and say that you did
("verified present at `README.md:485`"). One wrong anchor costs more than none.

Prefer linking over duplicating: this project treats a second copy of an opinion
as a second thing to keep true, so a fix that restates a skill inside another
document is likely to be redirected.
-->

## Open questions / decisions for the implementer

<!--
Real unknowns, each framed as a decision with a default — "X or Y, default X
because Z".

Delete this section if there are none.
-->

## Acceptance criteria

<!--
What "done" looks like, checkable against the merge commit of THIS issue alone.

For prose this is usually "the passage at X says Y" — which is fine, but state
it precisely enough that a resolver and a reviewer would agree on whether it
holds.
-->

## Area

<!--
Which subsystem this touches. `area:docs` covers the README and community/meta
documentation; a skill body is usually `area:skills`. List the current set with:

    gh label list --repo dbaggott/claude-plugins --search area

Name it here; the maintainer applies the label.
-->

## Required reading

<!--
Issues, PRs, or docs a resolver MUST read before starting. Keep this ruthlessly
short. Full URLs, never bare #19.

Delete this section if empty.
-->

## Related (optional)

<!--
Background only. Do not read unless blocked.

Delete this section if empty.
-->
