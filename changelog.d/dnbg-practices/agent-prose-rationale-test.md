`coding-practices` sharpens two rules about detail that costs more than it earns.

**Agent-facing prose now has a test for when rationale earns its line.** A
`SKILL.md`, rules file, or `CLAUDE.md` has two readers and charges one: the
executor loads every line on every run, the editor opens the file once. Ask
whether an executor that never read a line of rationale would act differently. A
*why* that decides a case the instruction doesn't enumerate stays; a *why* that
only defends the instruction against a future editor moves to the script's header
comment, a test name, or the PR. The section is renamed from "Four ways
agent-facing prose fails" to "What earns a line in agent-facing prose".

**A count of the list it introduces is now called out as a comment failure.**
"Four ways this fails"; "the three checks below" — the list counts itself, so no
reader acts on the number, and any added item silently falsifies it. The
neighbouring rule on specific values now names the general trade behind both: how
likely a detail is to need an edit, against whether a reader acts differently for
having it.
