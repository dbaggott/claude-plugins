# Design: the two vices, and log versus product

The long form behind `E2`–`E5` and `L1`–`L2` in `SKILL.md`. Open the first half when
deciding whether to extract, unify, or special-case; the second when choosing
between a logger and a stream.

## Two abstraction vices, not one (E2–E5)

The familiar caution against premature abstraction guards one vice —
**premature generalization**: building extensibility (parameters, hooks,
config, plugin points) for requirements that don't exist yet. The opposite vice
goes unnamed — **premature fragmentation**: treating two instances of *one*
problem as two problems, so a single responsibility ends up split across owners
or copied into several places. The first costs speculative complexity; the
second costs duplicated state that diverges and the same decision made in two
places — often the very bug you're now fixing. Both are real. Don't reach for
YAGNI as if avoiding abstraction were free; weigh the two costs against each
other.

The pull is nearly always toward avoiding generalization, so the corrective is
to give the second vice equal weight. The questions are different, and design
comes first:

- **Ask "who owns this decision/fact?" before "is generalizing premature?"**
  (E2). The first is a present-tense fact about the domain you can answer now;
  the second is speculation control. Answer the first and the second often
  dissolves — correct ownership tends to support the general case for free,
  because the owner handles all its cases. Same instinct as N2, naming a thing
  for what it is rather than how it's used: locate the thing, don't shape it
  around one caller.
- **Testability is the same question from the other side** (E3). Code that
  cannot be tested without standing up something unrelated is code whose
  decision lives next to something it doesn't own; moving the decision to its
  owner is what makes it testable in isolation.
- **A degenerate case is the same problem at a boundary — derive it, don't
  fork it** (E4). When you're about to special-case a "trivial", "edge", or
  "degenerate" instance, get it to fall out of the general path instead. If the
  general design *can't* express the degenerate case cleanly, that's evidence
  the general design is wrong — not that the case is separate. The degenerate
  case is a *test* of the design; folding it in is how you discover the design
  needs work, which is exactly why skipping it as "premature" hides the defect.

  ```python
  # don't — the single-stage case is forked from the multi-stage path
  def total_iteration_cap(stages):
      if len(stages) == 1:                 # "one stage — the loop is overkill"
          return stages[0].cap
      cap = 0
      for s in stages:
          cap += s.cap
      return cap

  # do — the general path already yields the one-stage answer; no fork to drift
  def total_iteration_cap(stages):
      return sum(s.cap for s in stages)
  ```

- **Distinguish unification from generalization-on-spec** (E5). Collapsing two
  real instances of one problem usually *removes* code (a branch, a copy) and
  is rarely premature; adding flexibility for absent requirements adds code and
  usually is. "Avoid premature abstraction" applies only to the second — don't
  let the word "general" make you recoil from the first. Duplicated logic is
  rarely just two copies of the same lines: it usually marks a responsibility
  that has no single owner, and a decision that is tested twice or not at all.
  Extracting it is how the decision gets one owner and one test. Forge the
  shared abstraction against the real consumers you have, and pressure-test its
  *shape* against every known instance — including the degenerate one — even
  when you build only one of them. The other instances prove the seam is in the
  right place; they don't all have to ship at once.

## Log or product (L1–L2)

Application code logs through its project's logging framework — never via a
raw `print` / `println` / `fmt.Print*` / `console.log` / `eprintln!` to stdout
or stderr. The framework carries level, structure, and routing (to a file, a
collector, an error tracker); a bare print drops all of that and lands wherever
the process's streams happen to point. Which framework is per-project
convention — follow what the project already uses (Go `log/slog`, Rust
`tracing`, Node `pino`) rather than introducing another.

The carve-out is output that **is the program's product**, not a log line:

- **Scripts and one-off tools** print freely — printing *is* their interface.
- **A program's user-facing output** — the result it exists to emit (query
  results, a computed value, `--help`/usage text, an error meant for the person
  at the terminal) — goes to stdout/stderr directly. That's the program talking
  to its user, not logging. An interactive tool that shares a terminal with the
  user or a wrapped child keeps its status lines on stderr *by design*; routing
  those through a structured logger would be the wrong behavior, not a fix.

The test is what the text is *for*: diagnostics about the program's own
operation are logs and belong in the framework; output the caller asked for is
product and belongs on the stream. When in doubt for a long-running service or
background worker, it's a log.
