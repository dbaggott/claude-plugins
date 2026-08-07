---
name: coding-practices
description: Core engineering principles — design and clarity over expediency, security as a first-class concern, DRY, clean self-documenting code, logging discipline (use a framework not stdout/stderr, one event per operation, no sensitive data, actionable WARN+), common smells to stop on, verifying what you don't know, using Context7 for library docs, and no human time estimates. Load when writing or reviewing code, naming things, deciding whether to add a comment or reviewing existing ones (what a comment must not carry, and emphasis as a budget), choosing how to emit log or diagnostic output, looking up library APIs, sizing work, or making a recommendation that rests on an unchecked assumption. Skip for pure config edits, non-code questions, and quick lookups where no logic is being authored.
---

# Coding practices

These apply to all code, regardless of language or repo.

Some of what a senior engineer would say here is already in the Claude Code default system prompt (default to no comments, don't narrate the code, don't reference the current task or caller in comments, no error handling for impossible cases, three similar lines beats a premature abstraction). The sections below add to that baseline rather than repeating it.

## Design and clarity over expediency

When two paths produce equivalent behavior but one has a worse shape — a misleading name, a leaky abstraction, a special case that doesn't fit — take the shaped one. If the tradeoff is non-obvious, note it in the PR description, not in a code comment.

## Security is as important as correctness

A correct feature with a security hole is a broken feature. Concretely:

- **Parameterize queries.** Never string-concat user input into SQL.
- **Quote shell arguments through a primitive** (`shlex.quote`, list-form `subprocess.run([...])`, etc.). Never f-string user input into `os.system` / `exec` / a shell.
- **Validate at the trust boundary** — request handlers, CLI entry points, queue consumers — not deep inside helpers. Once data is past the boundary, helpers should be able to trust it.
- **Secrets come from env or a secret manager.** Never log them, never commit them, never inline a default in code "for local dev."
- **Prefer the library's safe API to manual escaping** — a template engine's autoescape, an HTTP client's `params=` argument, an ORM's bound parameters.

If you write something insecure, fix it immediately rather than filing it as a follow-up.

## Keep code DRY

Duplicated logic invites drift. When you find yourself copy-pasting, extract.

(The system-prompt caveat — three similar lines beats a premature abstraction — still applies. Wait until the shape of the duplication is clear before pulling out a helper. But that caveat guards only *one* of two opposite design vices — see "Two abstraction vices" below for the other, which it says nothing about and which is just as costly.)

## Two abstraction vices, not one

"Three similar lines beats a premature abstraction" guards against one vice — **premature generalization**: building extensibility (parameters, hooks, config, plugin points) for requirements that don't exist yet. There is an opposite vice it says nothing about — **premature fragmentation**: treating two instances of *one* problem as two problems, so a single responsibility ends up split across owners or copied into several places. The first costs speculative complexity; the second costs duplicated state that diverges and the same decision made in two places — often the very bug you're now fixing. Both are real. Don't reach for YAGNI as if avoiding abstraction were free; weigh the two costs against each other.

The agent default leans hard toward avoiding generalization, so the corrective is to give the second vice equal weight. The questions are different, and design comes first:

- **Ask "who owns this decision/fact?" before "is generalizing premature?"** The first is a present-tense fact about the domain you can answer now; the second is speculation control. Answer the first and the second often dissolves — correct ownership tends to support the general case for free, because the owner handles all its cases. (Same instinct as the "what it is, not how it's used" naming rule below: locate the thing, don't shape it around one caller.)
- **A degenerate case is the same problem at a boundary — derive it, don't fork it.** When you're about to special-case a "trivial" / "edge" / "degenerate" instance, get it to fall out of the general path instead. If the general design *can't* express the degenerate case cleanly, that's evidence the general design is wrong — not that the case is separate. The degenerate case is a *test* of the design; folding it in is how you discover the design needs work, which is exactly why skipping it as "premature" hides the defect.

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

- **Distinguish unification from generalization-on-spec.** Collapsing two real instances of one problem usually *removes* code (a branch, a copy) and is rarely premature; adding flexibility for absent requirements adds code and usually is. "Avoid premature abstraction" applies only to the second — don't let the word "general" make you recoil from the first.
- **Rule of three counts real, present instances — not hypotheticals.** Two live consumers plus a bug caused by their divergence is already past the threshold; "wait for a third" is the wrong reading. Forge a shared abstraction against the ≥2 real consumers you have, and pressure-test its *shape* against every known instance — including the degenerate one — even when you build only one of them. (Pressure-test the shape, not the build scope: the other instances prove the seam is in the right place; they don't all have to ship at once.)

## Clean, self-documenting code

The system prompt covers the comment rules in general. The additions here are about *names*:

**Names do the work.** A well-named function, variable, or type makes the code legible without a comment. If a reader has to consult docs to understand a name, the name is wrong, not the docs.

**Prefer "what it is/does" names over "how it's used" names.** The first survives refactors and reuse; the second rots the moment a second caller appears. Name from inside the type, not from outside its usage.

```python
# don't — name describes one caller's perspective
def token_for_checkout_flow(user): ...

# do — name describes the thing
def payment_token(user): ...
```

**A name that collides with a dominant meaning misleads even when it's technically correct.** When a term already carries a strong meaning in the language or the domain, reusing it for something else makes every reader resolve the wrong sense first — accurate-but-colliding still costs comprehension. Pick the unambiguous word.

```
# don't — collides with the dominant meaning in this context
"route"    in a pipeline that also lays PCB copper  → reads as the routing stage
"closure"  for a worklist/result set               → reads as a captured-scope function

# do — the unambiguous term
"dispatch" (hand work to its owner) · "worklist" (the open set of items)
```

**When you do write a comment, write the *why*, not the *what*.**

```python
# don't — restates the code
counter += 1  # increment counter

# do — explains a non-obvious invariant
counter += 1  # bump before retry so the dedup key changes
```

## What a comment must not carry

A comment is the only artifact in a repo with nothing enforcing it. No test fails
when it goes stale, no build breaks, no formatter notices — it rots silently and
surfaces only if a reader happens to open both files. So the bar is not "is this
true?" but **"will this still be true after the next change, and does it change
what someone does?"** These six all fail that bar:

- **History.** No "this used to claim X", "restored after being deleted", "was
  first written as Y", or narration of the bug that prompted the change. The
  commit and the PR record how the code got here and stay accurate; a comment
  restating it drifts. State the present-tense fact and its consequence instead.
  This bites hardest on review fixes, where the pull to narrate the correction is
  strongest — the corrected fact stays, the correction goes.
- **Another file's conclusions.** Point at *where* something is handled, never at
  *what it decided*. A location pointer survives the other file changing its
  mind; "see X, which establishes Y" is false the moment X stops establishing Y,
  and nothing local will tell you.
- **Transient state.** Litmus: *if the world changes, is the only action required
  deleting this comment?* Then it isn't a comment — it's an issue, which closes
  when the state changes. Evidence and provenance belong in the commit message
  and PR body.
- **A restatement of the identifier.** `# the user's email` above `user_email`
  spends a line to say nothing.
- **A defence against a mistake nobody would make.** Anticipating an implausible
  misreading costs every real reader attention.
- **A rationale that belongs on the definition.** When passing a config value at
  a call site, set it plainly — the strategy, the options and why one is chosen
  live on the variable's own `description`. Two copies is one to keep in sync.
  Comment the call site only when the *choice* is surprising in a way the
  definition can't cover: a temporary override, an exception to a convention.

What stays is a **current, non-obvious constraint** — a platform behavior, a
fail-closed risk, two values that must move together. That is what comments are
for. So are provenance markers that change how much a reader should trust a claim
("observed, not deduced"; "unverified") — those describe a claim's standing now,
not its history.

**Prefer an assertion to a prose invariant.** A test fails loudly; a comment rots
quietly. General form: **enforceable > prose > nothing.**

## Emphasis is a budget, not decoration

A file with twenty `⚠️` markers has no warnings. Reserve `⚠️` and ALL-CAPS for
gate bypass, credential exposure, data loss, or outage — roughly one per file.
That is a test each marker must pass, not a quota: three is fine when all three
mark silent failures.

⚠️ **When stripping markers en masse, watch for the marker that is a
*referent*.** Cross-references like "see the ⚠️ at the top of this file" name the
glyph rather than decorating with it, and removing it leaves "See the at the top
of this file". No typechecker, linter or test catches that. **Fix it by naming
the target in prose, never by restoring the glyph** — restoring works today and
breaks at the next rebalancing, and the target's own marker may already be gone.
Grep `see the ⚠️` and `per the ⚠️` after any such pass.

## One-time setup doesn't belong in the repo

When a feature depends on one-time setup someone does once and never again — an org admin installing a GitHub App, provisioning a secret, flipping a repo toggle — keep those steps in the PR description that introduces the dependency. Don't capture them in the README or in long comment blocks inside source files.

**Why:** Setup steps don't add value sitting in the repo. They're done once and read forever, drifting from reality or distracting from the actual code intent. A future maintainer reading the file sees content that isn't true for them anymore — the system is already configured.

- A comment that explains *why* an unusual auth pattern is used is fine.
- A comment listing "and to make this work, an admin must do X, Y, Z" is not.
- Same for READMEs: avoid "Required one-time setup" sections. If a future maintainer needs to reproduce the setup, it belongs in onboarding docs or the relevant infrastructure-as-code module — close to where the setup actually happens — not in the consumer file.

## Logging

Application code logs through its project's logging framework — never via a raw `print` / `println` / `fmt.Print*` / `console.log` / `eprintln!` to stdout or stderr. The framework carries level, structure, and routing (to a file, a collector, an error tracker); a bare print drops all of that and lands wherever the process's streams happen to point. Which framework is per-project convention — follow what the project already uses (e.g. Go `log/slog`, Rust `tracing`, Node `pino`) rather than introducing another.

The carve-out is output that **is the program's product**, not a log line:

- **Scripts and one-off tools** print freely — printing *is* their interface.
- **A program's user-facing output** — the result it exists to emit (query results, a computed value, `--help`/usage text, an error meant for the person at the terminal) — goes to stdout/stderr directly. That's the program talking to its user, not logging. An interactive tool that shares a terminal with the user or a wrapped child keeps its status lines on stderr *by design*; routing those through a structured logger would be the wrong behavior, not a fix.

The test is what the text is *for*: diagnostics about the program's own operation are logs and belong in the framework; output the caller asked for is product and belongs on the stream. When in doubt for a long-running service or background worker, it's a log.

**Consolidate related facts into one event.** Prefer a single coherent log entry over several scattered lines describing the same operation — attach the details as fields on one event. A reader reconstructing what happened shouldn't have to stitch a story from five entries, and in structured logging the fields of one event are queryable together in a way separate lines never are. (Distinct attempts in a retry are separate events; this is about not fragmenting *one* event, not about collapsing a genuine sequence.)

**Never log sensitive data.** No passwords, tokens, credit-card numbers, or other PII — in the message *or* a structured field, at any level. This extends "never log secrets" from the security section above: logs are shipped to collectors, indexed, and retained far longer and more widely than the operation that produced them, so a sensitive value in a log is a leak with a long tail. Redact or omit at the call site; don't rely on a downstream scrubber to catch it.

**WARN and above must be actionable.** A record at WARN or higher asserts that someone should look — if nothing needs doing, it's INFO or DEBUG. A high level that fires routinely trains readers to tune the channel out, so the genuinely actionable records get missed too. Reserve them:

- **WARN** — something unexpected that was handled without user impact, but warrants investigation.
- **ERROR** — a serious failure affecting a specific request or operation.
- **FATAL/CRITICAL** — an unrecoverable condition that terminates the process.

## Stop on these smells

If you catch yourself doing any of these, stop and rethink before continuing:

- **Calling an API you haven't verified exists.** "I'm pretty sure it has a `.batch()` method" is a hallucination waiting to happen. Read the source or fetch the docs (see Context7 below).
- **Silencing an error you don't understand.** A `try/except: pass` you added to make the test green is a bug-shaped object. Understand why the error fires, then decide whether to handle it, fix the root cause, or let it propagate.
- **Claiming a UI or UX change works without opening it.** Type checks and tests verify code correctness, not feature correctness. If you can't run the app, say so explicitly instead of asserting the change works.
- **Writing a wrapper that only forwards arguments.** `def foo(x, y): return bar(x, y)` — either `foo` adds value (renaming, validating, defaulting) or the caller should just call `bar`. Don't introduce indirection for its own sake.
- **A poll loop with no deadline and no guard on its exit condition.** A `while`/`until` that stops only when some state appears (a review on a SHA, a run reaching `completed`) spins forever the moment that state becomes unreachable — an empty variable baked into the condition, an expired token that turns every probe into an error, a status string outside the set you match. Give every poll loop a deadline (or max-iteration cap) *and* a guard against an unsatisfiable condition, so a stuck loop exits and surfaces instead of becoming a runaway background shell.
- **Declaring a feature removal complete after grepping only the feature's name.** A feature introduces a whole vocabulary — flag names (`--plan-file`), JSON/multipart field names (`"plan"`, `effective_plan_file`), struct fields (`PlanPath`), file extensions, fixtures — and a name-only sweep clears files that reference the feature solely through those other identifiers. Before calling a removal done, list every identifier family the feature introduced and run one sweep per family across every affected repo. "This file doesn't mention the feature name" is not evidence it's clean.
- **Documenting why a feature *isn't* supported instead of just omitting it.** When a flag/option/feature is intentionally unsupported on a CLI or API surface, leave it out of the help/usage text entirely — no parenthetical, callout, or paragraph explaining that it doesn't work or what to use instead. Listings of non-features are clutter that grows over time and train readers to skim past the real options; absence is how "not a feature" is communicated. (If a shared parser would otherwise silently accept the input, keep the runtime rejection + error — that fires only on use and is a different category from preemptive docs.)

## Verify what you don't know

Be honest about what you've checked and what you're guessing:

- **Read before changing.** Before editing a function, read it — and ideally a caller or two. Don't infer behavior from the name.
- **Say "I haven't verified X" out loud.** If a recommendation hinges on an unchecked assumption, name the assumption rather than presenting it as fact. Same for code: if you're proposing a snippet whose API call you're not 100% sure about, flag it instead of asserting it works.
- **For library APIs, use Context7 (below) or read the installed source.** Don't write code from memory for an API you haven't used recently.

## Use Context7 for library documentation

When you need to consult docs for a library, framework, or external API, use the **Context7 MCP server** rather than relying on training-time knowledge. Context7 fetches current, version-specific docs on demand — the same source the library's own docs site renders from. Training data goes stale: APIs are renamed, parameters added, deprecations land.

Typical flow:

1. `mcp__context7__resolve-library-id` — get the canonical id for the library.
2. `mcp__context7__get-library-docs` — fetch docs for that id, optionally scoped to a topic.

Use it when:

- You're calling an API you haven't used recently.
- You're unsure whether a function signature, option name, or default has changed.
- A code sample you'd otherwise write from memory could plausibly be wrong.

Skip it for:

- Language standard library and other stable built-ins.
- Project-internal code — read the source.

If Context7 isn't configured on this machine, say so and read the installed package's source (e.g. `node_modules/<pkg>`, the site-packages path, or the vendored copy) rather than guessing.

## No human time estimates

Do not size work in hours, days, or weeks. AI does the implementation; calendar-time estimates are meaningless. If sizing is useful, describe it in terms of:

- **Scope** — lines of code, files touched, subsystems involved.
- **Risk** — well-understood vs. exploratory; mechanical vs. judgment-heavy.

These compose: a 500-line change inside one subsystem you've shipped a dozen times is *not* the same size as a 500-line change spanning three subsystems with an unknown integration shape. Lead with whichever dimension dominates the work.
