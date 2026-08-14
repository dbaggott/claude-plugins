`coding-practices` now gives agent-facing prose a test for when rationale earns
its line, rather than only listing ways such prose fails.

A `SKILL.md`, rules file, or `CLAUDE.md` has two readers and charges one: the
executor loads every line on every run, the editor opens the file once. The
section — renamed from "Four ways agent-facing prose fails" to "What earns a line
in agent-facing prose" — asks whether an executor that never read a line of
rationale would act differently. A *why* that decides an unenumerated case stays;
a *why* that only defends the instruction against a future editor moves to the
script's header comment, a test name, or the PR.
