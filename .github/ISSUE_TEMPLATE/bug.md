---
name: Bug
about: Something in a plugin, hook, skill, or script behaves incorrectly
title: ''
labels: bug
assignees: ''
---

<!--
This issue will most likely be picked up cold — by a fresh agent session, or by
someone who has not read this thread. Everything a resolver needs should be
readable here without clicking through. See CONTRIBUTING.md for the reasoning.

Delete any section that genuinely does not apply, rather than leaving it empty.
-->

## Problem

<!--
What happens, and what should happen instead. Name the specific hook, skill,
script, or workflow. If you have a repro, it goes here — the exact command, the
payload, the observed output.
-->

## Environment

<!--
Only what is load-bearing for this bug. Claude Code version, OS, and whether
`jq` / `git` / `gh` are present matter for hook behavior; most other details do
not. Note whether the repo you hit this in was covered by your `owners` config —
the gates are inert outside it, which changes what the symptom means.
-->

## Proposed approach

<!--
If you already know the fix or the direction, state it — this is the highest-
value section in the whole body, because the context that produced it dies with
your session.

Name the specific files and functions. VERIFY EACH ANCHOR against the current
tree before filing, and say that you did ("verified present at
`dnbg-workflow/hooks/lib.sh:100`"). One wrong anchor costs more than none: the
resolver stops trusting the body and re-researches everything.

If you considered an alternative and rejected it, say why — the rejection
rationale is what stops the resolver rediscovering the same dead end.

If you genuinely have no proposed fix, say so explicitly rather than leaving
this blank.
-->

## Open questions / decisions for the implementer

<!--
Real unknowns, each framed as a decision with a default — "X or Y, default X
because Z" — never as an open musing. Without the default form the resolver
stalls or silently picks.

Delete this section if there are none.
-->

## Acceptance criteria

<!--
What "done" looks like, checkable against the merge commit of THIS issue alone.
A criterion that needs something another issue introduces cannot be run here —
move it to that issue and leave a pointer.

Prefer criteria that are runnable commands. For this repo that usually means a
bats case in `tests/`.
-->

## Area

<!--
Which subsystem this touches. List the current set with:

    gh label list --repo dbaggott/claude-plugins --search area

Name it here; the maintainer applies the label. If none fits, say so — a new
`area:*` label may be warranted, but the set stays human-curated.
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
