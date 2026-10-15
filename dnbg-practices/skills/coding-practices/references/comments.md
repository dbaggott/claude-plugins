# Comments: the bar, case by case

The long form of the `C` rules in `SKILL.md`. Open it before adding or keeping a
comment, and when reviewing a diff that adds or changes one.

## Contents

- The bar (C1–C3)
- History (C4)
- Another file's conclusions (C5)
- Transient state (C6)
- A restatement of the identifier (C7)
- A confirmation of what the reader already assumes (C8)
- A defence against a mistake nobody would make (C9)
- A warning about what breaks if the code changes (C10)
- A rationale that belongs on the definition (C11)
- A specific value the point doesn't rest on (C12)
- A count of the list it introduces (C13)
- Why a feature isn't supported (C14)
- Emphasis that fails the severity test (C15)
- A cross-reference that names a glyph (C16)

## The bar (C1–C3)

A comment is an artifact with nothing enforcing it. No test fails when it goes
stale, no build breaks, no formatter notices — it rots silently and surfaces
only if a reader happens to open both files. So the bar is not "is this true?"
but **"will this still be true after the next change, and does it change what
someone does?"**

**C1.** When you do write a comment, write the *why*, not a restatement of the
code. A stretch of code with no name of its own — a block of steps inside a
function — can take a line saying what it is for; a named function already has
one, and repeating it is the restatement below.

```python
# don't — restates the code
counter += 1  # increment counter

# do — explains a non-obvious invariant
counter += 1  # bump before retry so the dedup key changes
```

**C2.** What stays is a **current, non-obvious constraint** — a platform
behavior, a fail-closed risk, two values that must move together. So are
provenance markers that change how much a reader should trust a claim
("observed, not deduced"; "unverified") — those describe a claim's standing
now, not its history.

**C3.** Prefer an assertion to a prose invariant. A test fails loudly; a
comment rots quietly. General form: **enforceable > prose > nothing.** Once the
assertion lands, the prose it displaces goes with it; see C10.

## History (C4)

No "this used to claim X", "restored after being deleted", "was first written
as Y", or narration of the bug that prompted the change. The commit and the PR
record how the code got here and stay accurate; a comment restating it drifts.
State the present-tense fact and its consequence instead. This bites hardest on
review fixes, where the pull to narrate the correction is strongest — the
corrected fact stays, the correction goes.

## Another file's conclusions (C5)

Point at *where* something is handled, never at *what it decided*. A location
pointer survives the other file changing its mind; "see X, which establishes
Y" is false the moment X stops establishing Y, and nothing local will tell you.

## Transient state (C6)

Litmus: *if the world changes, is the only action required deleting this
comment?* Then it isn't a comment — it's an issue, which closes when the state
changes. Evidence and provenance belong in the commit message and PR body.

## A restatement of the identifier (C7)

`# the user's email` above `user_email` spends a line to say nothing.

## A confirmation of what the reader already assumes (C8)

A comment stating how something behaves earns its line by naming a *deviation*
from what a competent reader expects, never by agreeing with the expectation.
Against "this `types:` list replaces the defaults rather than extending them",
a comment would be worth writing only if the list *extended* them.

## A defence against a mistake nobody would make (C9)

Anticipating an implausible misreading costs every real reader attention.

## A warning about what breaks if the code changes (C10)

State the property the code holds, positively — that is what a reader needs in
a case the warning doesn't enumerate. "Re-pointing hands one account's
credential to another" earns its line; "an implementation that assigned
unconditionally would leave that open" does not.

**Where a test already fails on the change being warned against, the guard
goes** — both the argument for it and the restatement of the behaviour it pins
are second copies of what the test holds, and the copies are what rot. Litmus
for whether a test pins it: *if I made the change this warns against, would
something go red?* What stays either way is why the behaviour matters, which no
test carries.

## A rationale that belongs on the definition (C11)

When passing a config value at a call site, set it plainly — the strategy, the
options and why one is chosen live on the variable's own `description`. Two
copies is one to keep in sync. Comment the call site only when the *choice* is
surprising in a way the definition can't cover: a temporary override, an
exception to a convention. The same holds for a comment that would fit at
several call sites: make it once, where the thing is defined, rather than
pasting it at each.

## A specific value the point doesn't rest on (C12)

"The token expires after 1 hour, so re-mint rather than reusing it" — when the
issuer makes it two hours, the advice is still right and the comment is now
wrong. Nothing forces the fix, so nobody makes it. This one slips past the
transient-state litmus in C6: the answer there is "no, I'd edit the number",
and it rots regardless.

**Test: would a different value change what the reader does?** If not, name
the property and drop the number — "short-lived; mint per use". The two halves
are independent: how likely the detail is to need an edit, and whether a reader
acts differently for having it. Detail scoring badly on both is pure carrying
cost, numbers or not.

When the value *is* load-bearing — a limit the reader must respect, a constant
that must match another — keep it, and put it where it can be checked: on the
line with the literal it explains, or asserted, per C3. A number restated at a
distance from its source is a copy, and copies drift.

## A count of the list it introduces (C13)

"Four ways this fails"; "the three checks below". The clearest case of the C12
trade: the list counts itself, so no reader acts on the number, and any added
item silently falsifies it — the prose still reads fine, so nothing catches
it. Write "these fail" and let the list say how many.

**Where the count scopes a subset, name the members instead of dropping it.**
"These three carry a handoff" over a list of seven is a count doing two jobs,
and deleting the number leaves "these", which now claims all seven. Naming them
— "`COMMITS`, `ACTIVITY` and `READY` carry a handoff" — drops the count and
keeps the scope, and stays right when a fourth joins them. Check which job the
number is doing before removing it: over a whole list it is redundant, over a
subset it is the only thing bounding the claim.

## Why a feature isn't supported (C14)

When a flag, option, or feature is intentionally unsupported on a CLI or API
surface, leave it out of the help or usage text entirely — no parenthetical,
callout, or paragraph explaining that it doesn't work or what to use instead.
Listings of non-features are clutter that grows over time and train readers to
skim past the real options; absence is how "not a feature" is communicated.

If a shared parser would otherwise silently accept the input, keep the runtime
rejection and its error — that fires only on use, and is a different category
from preemptive docs.

## Emphasis that fails the severity test (C15)

A `⚠️` or ALL-CAPS marker asserts that ignoring the line causes gate bypass,
credential exposure, data loss, or outage. A marker that fails that test is
removed, and a file with twenty markers has no warnings. Zero is the right
number for most files.

Most markers sit on a comment that fails C10 — a warning about what breaks if
the code changes — so the bar removes them before the marker question arises.

## A cross-reference that names a glyph (C16)

"See the ⚠️ above" breaks into "See the above" the moment that marker is
removed under C15, and nothing catches it. Name the target in prose.
