---
name: Enhancement
about: A new capability, or a change to how an existing one works
title: ''
labels: enhancement
assignees: ''
---

<!--
This issue will most likely be picked up cold — by a fresh agent session, or by
someone who has not read this thread. Everything a resolver needs should be
readable here without clicking through. See CONTRIBUTING.md for the reasoning.

Before filing: read the "Scope" section of CONTRIBUTING.md. Changes to the
project's opinions themselves — the worktree/draft-PR flow, CalVer,
fragments-drive-releases, the self-documenting issue body — are the product
rather than incidental choices, and are usually declined. That is a discussion
worth having in an issue; it is not usually a PR.

Delete any section that genuinely does not apply, rather than leaving it empty.
-->

## Problem

<!--
What is missing or wrong today, and what it costs. Lead with the problem rather
than the solution — an enhancement whose motivation is only "it would be nice"
is hard to evaluate and easy to decline.
-->

## Proposed approach

<!--
The direction, in enough detail that a resolver does not have to re-derive it.
Name the specific files, skills, or hooks involved.

VERIFY EACH ANCHOR against the current tree before filing, and say that you did
("verified present at `dnbg-workflow/skills/git-workflow/SKILL.md:104`"). One
wrong anchor costs more than none.

Say where the content belongs — skill, always-on rule, or the consuming repo's
CLAUDE.md — and why. Default to the cheapest that fits; see
README.md#where-new-content-goes-skill-vs-always-on-vs-project-claudemd.
Always-on is charged to every session and every subagent of every user, so it
needs a reason a skill description could not fire on.

Alternatives considered and rejected, with the reason, belong here too.

If this is genuinely open-ended, say so explicitly — "no preferred approach;
evaluate X vs Y and pick" — so the resolver knows the openness is intentional
rather than an omission.
-->

## Open questions / decisions for the implementer

<!--
Real unknowns, each framed as a decision with a default — "X or Y, default X
because Z" — never as an open musing.

Delete this section if there are none.
-->

## Acceptance criteria

<!--
What "done" looks like, checkable against the merge commit of THIS issue alone.
A criterion that needs something another issue introduces cannot be run here.

Note honestly which criteria are mechanically checkable and which are not. Much
of this repo ships instructions to a model, and "the model follows the rule" is
not something the test suite can assert — say so rather than writing a criterion
that will be ticked by inspection and read as tested.
-->

## Area

<!--
Which subsystem this touches. List the current set with:

    gh label list --repo dbaggott/claude-plugins --search area

Name it here; the maintainer applies the label. If none fits, say so.
-->

## Required reading

<!--
Issues, PRs, or docs a resolver MUST read before starting. Keep this ruthlessly
short — every entry is a context tax. Full URLs, never bare #19.

Delete this section if empty.
-->

## Related (optional)

<!--
Background only. Do not read unless blocked.

Delete this section if empty.
-->
