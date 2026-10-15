# What earns a line in agent-facing prose

The long form of the `P` rules in `SKILL.md`. Open it before authoring or
reviewing anything that instructs an agent — a `SKILL.md`, an always-on rules
file, a `CLAUDE.md`.

## Two readers, one of them charged (P1)

The comment bar applies to this prose in full: nothing enforces it either, and
its reader can't ask a follow-up, so a stale line gets acted on rather than
queried. **History** is what it accretes fastest: every incident invites a
paragraph explaining itself, and none is ever removed.

On top of that bar is a problem a comment does not have. The **executor** loads
every line on every run and acts on it. The **editor** opens the file once, to
change it. Rationale aimed at the editor — why the instruction is shaped this
way, what broke before it existed — is paid for on every run and acted on by
none.

**So test every line of rationale: would an executor that never read it do
something different?** Often yes, and then it stays — a *why* that lets the
agent choose correctly in a case the instruction doesn't enumerate is doing
work no list of steps can. What goes is the *why* that only defends the
instruction against whoever might one day change it — that belongs where its
reader looks: the script's own header comment, a test name, the PR that
introduced it. Prefer the enforceable home, since a case a test pins cannot be
simplified away and needs no paragraph standing guard over it.

## The same argument twice in the same place (P2)

Rationale that passes the test above earns one line, at the instruction. A
second paragraph defending a choice the instruction already carries is spent
attention; the PR is where a reviewer wants that argument. This is distinct
from C11, a rationale that belongs on the definition: that one is about the
wrong **place**, this one is about a second copy.

## The inverse of a condition (P3)

A section scoped "when X" does not also need "when not X, none of this
applies". The agent read the heading.

## A read an earlier step could have carried (P4)

When a step needs one more field, add it to the fetch the flow already makes
rather than issuing a second call for it — the duplicate costs a round trip on
every run, and nothing in the prose marks it as avoidable.

## A branch for a state the install cannot be in (P5)

Not the implausible *misreading* of C9 — an instruction for a real case that
this deployment never produces. It is read every run, and it invites the agent
to go looking for the case.
