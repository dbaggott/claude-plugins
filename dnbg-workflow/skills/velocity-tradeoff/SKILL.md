---
name: velocity-tradeoff
description: How to size and split work in a project that has explicitly opted into trading safety margin for speed — land whole capabilities in one PR instead of fragmenting into "safe" increments, skip backwards-compat and migration shims, and keep automated test coverage heavy anyway. Load when deciding whether to split a change across PRs, proposing a "step 1 now, follow-up later" plan, weighing a migration shim or feature flag, or sizing a change in a repo whose CLAUDE.md opts into this skill. Skip entirely unless the project opted in — this trades away protections most projects need.
---

# Velocity tradeoff

**This skill only applies where a project has opted in.** It trades away
protections that production software needs, so it is wrong by default. Check
before applying it: the project's `CLAUDE.md` (or the operator, directly) has to
opt in. If neither does, stop — the ordinary defaults apply, and nothing below is
in force.

A repo opts in with a short section in its own `CLAUDE.md` — a section rather
than a line, because the opt-in has to carry two things, and the second is the
one people leave out:

> ## How to size a change here
>
> Load `dnbg-workflow:velocity-tradeoff` when sizing a change or deciding
> whether to split a PR. <Project> is on the velocity side of that skill's
> risk/benefit trade.
>
> Per that skill's own framing this is a ratio, not a fact about the project, so
> the inputs it weighs can move. **Say something when you notice one of them
> moving.** But this opt-in comes out when the operator decides it comes out —
> not on an agent's read of the inputs.

The posture is the first thing; **who can unmake it** is the second. Write both.
An opt-in that states only the posture reads as permanent, and nothing in the
repo tells the next agent whose call it is to end.

Don't restate the rest of this skill in that section — point at it. A copy of the
inputs below is a second thing to keep true, and it will drift.

## What this trades, and how to tell whether the trade holds

This skill spends **safety margin** to buy **speed**. Whether that's a good buy
is a *ratio*, not a property of the project — and the common mistake is treating
one input as the whole test. "Does it have users?" is the largest single term in
that ratio. It is not the ratio.

Weigh all of it:

- **Blast radius.** What is the worst a bad change does? A broken page someone
  reloads costs a minute. Corrupted stored data, money moved, or a leaked
  credential cannot be reloaded away. **Irreversible damage vetoes the trade**
  however favorable everything else looks.
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
  expensive even when every other factor is favorable.

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

- **Not a license to skip review.** Bigger PRs need review more, not less.
- **Not a license to ship known-broken code.** A bounded blast radius makes a
  *design* choice cheap to revisit; it never makes a bug acceptable.
- **Two different decisions, and only one of them is yours.** Keep them apart —
  conflating them either neuters the veto above or turns one cautious change into
  a silent revocation.

  **Revoking the opt-in is the operator's.** You don't get to decide the trade has
  stopped holding and quietly start splitting everything again. When you notice an
  input moving — users arriving is the obvious one, but so is the blast radius
  growing (the project starts storing something it cannot regenerate), rollback
  ceasing to be one command, or test coverage thinning — raise it, keep following
  the opt-in, and let them decide.

  **Declining the posture for a single change is yours, and it is a duty rather
  than a liberty.** The irreversible-damage veto above applies per *change*, not
  per project: a migration that rewrites data in place is outside this posture
  whatever the repo opted into. Size that one conservatively, split it if
  splitting is what makes it recoverable, and say why you did. What you must not
  do is generalize from it — one one-way door is not evidence the opt-in is
  stale.
