---
name: prototype-velocity
description: How to size and split work in a project where the risk/benefit ratio favours speed over safety margin — land whole capabilities in one PR instead of fragmenting into "safe" increments, skip backwards-compat and migration shims, and keep automated test coverage heavy anyway. Load when deciding whether to split a change across PRs, proposing a "step 1 now, follow-up later" plan, weighing a migration shim or feature flag, or sizing a change in a repo whose CLAUDE.md opts into this skill. Skip entirely unless the project opted in — this trades away protections most projects need.
---

# Prototype velocity

**This skill only applies where a project has opted in.** It trades away
protections that production software needs, so it is wrong by default. Check
before applying it: the project's `CLAUDE.md` (or the operator, directly) has to
opt in. If neither does, stop — the ordinary defaults apply, and nothing below is
in force.

Opting a repo in is one line in its `CLAUDE.md`:

> This project is prototype-stage — load `dnbg-workflow:prototype-velocity` when
> sizing a change or deciding whether to split a PR.

## What this trades, and how to tell whether the trade holds

This skill spends **safety margin** to buy **speed**. Whether that's a good buy
is a *ratio*, not a property of the project — and the common mistake is treating
one input as the whole test. "Does it have users?" is the largest single term in
that ratio. It is not the ratio.

Weigh all of it:

- **Blast radius.** What is the worst a bad change does? A broken page someone
  reloads costs a minute. Corrupted stored data, money moved, or a leaked
  credential cannot be reloaded away. **Irreversible damage vetoes the trade**
  however favourable everything else looks.
- **Reversibility, and how fast.** A one-command redeploy or rollback makes a
  large change cheap to get wrong. A migration that rewrites data in place does
  not — that is a one-way door wearing the costume of an ordinary PR.
- **How soon breakage is noticed.** By you, within five minutes of deploying? Or
  by someone else, silently, next week? The lag between a fault and its discovery
  is what turns a small one into a large one.
- **Automated test coverage.** This is what *buys the margin back*, and it is the
  half that is not optional — see below.
- **Users: how many, and how forgiving.** The dominant term. Zero, or "just me",
  makes almost anything cheap to get wrong. Real users make the same change
  expensive even when every other factor is favourable.

Because it is a ratio, the corners are real and both of them occur: a project
with a handful of forgiving users, instant rollback and heavy tests can sit
comfortably on the velocity side. A project with **zero** users performing an
irreversible data migration does not.

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
first place — in the ratio above, it is the term you control most directly. A
project that drops its tests to go faster has traded velocity for the appearance
of velocity: the next big PR lands blind, and the blast-radius and detection-lag
terms both get worse at once.

The asymmetry is the whole point: cut *manual* verification, keep *automated*
verification.

## What this does not license

- **Not a licence to skip review.** Bigger PRs need review more, not less.
- **Not a licence to ship known-broken code.** A bounded blast radius makes a
  *design* choice cheap to revisit; it never makes a bug acceptable.
- **Not yours to revoke.** The opt-in is a judgement its author made and only
  they can unmake — you don't get to decide the trade has stopped holding and
  quietly start splitting PRs again. What you *should* do is say something when
  you notice the inputs moving: users arriving is the obvious one, but so is the
  blast radius growing (the project starts storing something it cannot
  regenerate), rollback ceasing to be one command, or test coverage thinning.
  Raise it, keep following the opt-in, and let the operator decide.
