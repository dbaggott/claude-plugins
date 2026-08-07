---
name: prototype-velocity
description: How to size and split work in a project that has explicitly opted into prototype-stage velocity — land whole capabilities in one PR instead of fragmenting into "safe" increments, skip backwards-compat and migration shims, and keep automated test coverage heavy anyway. Load when deciding whether to split a change across PRs, proposing a "step 1 now, follow-up later" plan, weighing a migration shim or feature flag, or sizing a change in a repo whose CLAUDE.md opts into this skill. Skip entirely unless the project opted in — the tradeoffs here are wrong for anything with real users.
---

# Prototype velocity

**This skill only applies where a project has opted in.** It trades away
protections that production software needs, so it is wrong by default. Check
before applying it: the project's `CLAUDE.md` (or the operator, directly) has to
say this project is prototype-stage. If neither does, stop — the ordinary
defaults apply, and nothing below is in force.

Opting a repo in is one line in its `CLAUDE.md`:

> This project is prototype-stage — load `dnbg-workflow:prototype-velocity` when
> sizing a change or deciding whether to split a PR.

## The stance

A prototype-stage project has no end users. The usual production constraints —
risk-free incremental rollout, backwards-compat, migration shims, feature-flag
gating — do not apply. Optimize for **velocity** and for cutting **manual-testing
overhead**, not for minimizing per-change risk.

## Land a whole capability in one PR

Don't split a logical change into a sequence of "safe" increments, and don't
propose "step 1 now, follow-up PR later." Agents over-fragment by default, and
each PR boundary is another round of manual verification — exercising a deployed
instance, confirming a deploy is live, eyeballing behavior.

The cost being minimized is repeated *manual* testing, which fragmenting a change
across PRs multiplies.

## Keep automated test coverage heavy

Test coverage is **not** the overhead to cut. It is what lets the project move
fast with less risk, and it is what makes the bigger chunks safe to land in the
first place. A prototype that drops its tests to go faster has traded velocity
for the appearance of velocity — the next big PR lands blind.

The asymmetry is the whole point: cut *manual* verification, keep *automated*
verification.

## What this does not license

- **Not a licence to skip review.** Bigger PRs need review more, not less.
- **Not a licence to ship known-broken code.** "No end users" bounds the blast
  radius of a *design* choice; it doesn't make a bug acceptable.
- **Not permanent.** The moment the project has users, this skill stops applying
  and the repo's opt-in line should come out. If you notice that has happened and
  the line is still there, say so.
