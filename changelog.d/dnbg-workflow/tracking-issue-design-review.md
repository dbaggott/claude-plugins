New: a shape for **tracking issues** — an issue whose body is a project's design
and the parent of the issues that implement it. `issue-workflow` now describes
its sections, stable `C#`/`R#`/`D#`/`Q#`/`A#` IDs, decision and open-question
formats, decision and friction logs, and what makes a design accepted.

`issue-reviewer` gains a design mode: reviewing a tracking issue's body also
checks that requirements are checkable, every decision has a rationale and a
reversal condition, every open question has a default, end-to-end criteria
exist, and every cited ID resolves. The round comment names the mode and lists
each check it ran.
