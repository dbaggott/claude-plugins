---
name: coding-practices
description: Engineering rules with citable IDs — design over expediency, security, naming, the comment bar, agent-facing prose, logging, verification, sizing. Load when writing or reviewing code, naming things, weighing whether to add or keep a comment, choosing how to emit log or diagnostic output, looking up library APIs, sizing work, making a recommendation that rests on an unchecked assumption, or authoring prose that instructs an agent (a SKILL.md, an always-on rules file, a CLAUDE.md) — the comment bar governs those too. Skip for pure config edits (settings.json, lockfiles), questions that author nothing, and quick lookups where no logic is being written.
---

# Coding practices

Extensions, not a baseline: what a senior engineer would state first is
assumed, and where your harness or your project states something this file
touches, that source wins.

Every rule has an ID. A review finding cites the ID and says what to change;
it does not restate the rule's argument. IDs are never reused, so a dropped
rule leaves a gap.

## Every change (E)

- **E1 Take the better shape.** Between two paths with the same behavior, take
  the one without the misleading name, the leaky abstraction, or the special
  case that doesn't fit. A non-obvious tradeoff goes in the PR description.
- **E2 Ask who owns this decision before asking whether generalizing is
  premature.** Ownership is answerable now, and the right owner tends to handle
  the general case for free.
- **E3 Code you cannot test without standing up something unrelated has its
  responsibility in the wrong place.** That is E2 failing, not a test-setup
  problem.
- **E4 A degenerate case is the same problem at a boundary: derive it from the
  general path, don't fork it.** A general design that cannot express it
  cleanly is the defect.
- **E5 Unifying two real instances of one problem is rarely premature; adding
  flexibility for absent requirements usually is.** Duplicated logic marks a
  responsibility with no single owner and a decision tested twice or not at
  all; extracting it gives both one home.
- **E6 A wrapper that only forwards its arguments is indirection for its own
  sake.** Either it adds something or the caller calls the target.
- **E7 Every poll loop has a deadline and a guard on an unsatisfiable
  condition.** Otherwise it spins forever once the state it waits for becomes
  unreachable.
- **E8 An error silenced without understanding why it fires is a bug-shaped
  object.** Understand it, then handle it, fix the cause, or let it propagate.
- **E9 One-time setup lives in the PR that introduced the dependency**, not in
  a README or a source comment. Steps a maintainer must be able to repeat go
  in onboarding docs or the infrastructure-as-code module that does the setup.

Open `references/design.md` before extracting, unifying, or special-casing;
it argues E2–E5 in full, with the degenerate-case example.

## Security (S)

A correct feature with a security hole is a broken feature.

- **S1** Parameterize queries; never concatenate input into SQL.
- **S2** Pass shell arguments through a quoting primitive or list form; never
  interpolate input into a shell string.
- **S3** Validate at the trust boundary — request handler, CLI entry point,
  queue consumer — so helpers past it can trust their input.
- **S4** Secrets come from the environment or a secret manager: never logged,
  never committed, never defaulted in code.
- **S5** Prefer the library's safe API — autoescape, bound parameters, a
  `params=` argument — to manual escaping.
- **S6** An insecure line is fixed now, not filed as a follow-up.

## Naming (N)

- **N1 Names do the work.** If a reader has to consult docs to understand a
  name, the name is wrong, not the docs.
- **N2 Name what a thing is or does, not how one caller uses it.** The
  second rots when another caller appears.
- **N3 A term with a dominant meaning in the language or the domain misleads
  when reused for something else**, even when technically correct. Pick the
  unambiguous word.

  ```
  # don't — "route" in a pipeline that also lays PCB copper reads as the routing stage
  # do    — "dispatch" (hand work to its owner)
  ```

## Comments (C)

The bar: **will this still be true after the next change, and does it change
what someone does?** Nothing enforces a comment, so it rots silently.

- **C1 A comment carries the why, never a restatement of the code.** A block
  with no name of its own can take a line saying what it is for; a named
  function already has one.
- **C2 What stays is a current, non-obvious constraint**, or a provenance
  marker that changes how far to trust a claim ("observed, not deduced").
- **C3 Enforceable > prose > nothing.** Prefer an assertion to a prose
  invariant, and once the assertion lands, the prose it displaces goes with it.

These fail the bar:

- **C4** History: what this used to say, or the bug that prompted the change.
- **C5** Another file's conclusions. Point at where, never at what it decided.
- **C6** Transient state, where the only action when the world changes is
  deleting the comment. That is an issue.
- **C7** A restatement of the identifier.
- **C8** A confirmation of what a competent reader already assumes. A comment
  earns its line by naming a deviation.
- **C9** A defence against a mistake nobody would make.
- **C10** A warning about what breaks if the code changes. State the property
  positively, and where a test already pins it, the guard goes.
- **C11** A rationale that belongs on the definition, repeated at a call site.
- **C12** A specific value the point doesn't rest on. Test: would a different
  value change what the reader does?
- **C13** A count of the list it introduces. Where the count scopes a subset,
  name the members instead.
- **C14** Why a feature isn't supported. Absence says "not a feature"; a
  runtime rejection is a different category and stays.
- **C15** An emphasis marker — `⚠️`, ALL-CAPS — on a line whose neglect does
  not cause gate bypass, credential exposure, data loss, or outage.
- **C16** A cross-reference that names a glyph ("see the `⚠️` above"). Name the
  target in prose.

Open `references/comments.md` before adding or keeping a comment, or
reviewing a diff that does; it carries the long form of each case.

## Agent-facing prose (P)

A `SKILL.md`, a rules file, a `CLAUDE.md`: the comment bar applies, plus a
problem a comment does not have. The **executor** loads every line on every
run; the **editor** opens the file once.

- **P1 Test every line of rationale: would an executor that never read it do
  something different?** A why that decides a case the instruction doesn't
  enumerate stays; one that only defends the instruction against its next
  editor goes where that reader looks, the PR or a test name.
- **P2** The same argument twice in the same place. Rationale earns one line,
  at the instruction.
- **P3** The inverse of a condition. "When X" does not also need "when not X,
  none of this applies".
- **P4** A read an earlier step could have carried. Add the field to the fetch
  the flow already makes.
- **P5** A branch for a state this install cannot be in.

Open `references/agent-prose.md` before authoring or reviewing anything that
instructs an agent; it carries the executor/editor test in full and the long
form of each failure.

## Logging (L)

- **L1 Application code logs through the project's logging framework**, never
  a bare print to a stream. Follow the framework the project already uses.
- **L2 Output that is the program's product goes to the stream.** A script's
  output, a program's user-facing result, and an interactive tool's status
  lines are product. Diagnostics about the program's own operation are logs.
- **L3 One operation, one event.** Attach the details as fields on a single
  entry rather than scattering them over several lines. Distinct retry attempts
  are distinct events.
- **L4 Never log sensitive data**, in the message or a field, at any level.
  Redact at the call site.
- **L5 WARN and above must be actionable.** A record at that level asserts
  someone should look; if nothing needs doing, it is INFO or DEBUG.

Open `references/design.md` when choosing between a logger and a stream; its
second half is L1 and L2 case by case.

## Verification (V)

- **V1 Read before changing.** Read the function and a caller or two; don't
  infer behavior from the name.
- **V2 Name what you haven't checked.** Say so when a recommendation or a
  snippet rests on an unchecked assumption.
- **V3 Verify a library API against the installed source or current docs;
  never write a call, signature, option, or default from memory.** The
  standard library and stable built-ins are exempt; project code is V1.
- **V4 A UI or UX change is not done until you have opened it.** Tests cover
  the code, not the feature. If you can't run the app, say so.
- **V5 A changed test assertion needs a stated reason.** Before editing an
  assertion to make a test pass, name in the PR what the test protected and why
  that is no longer the contract. Rewriting it to go green is E8 in another
  form.
- **V6 A removal is not complete after grepping only the feature's name.** List
  every identifier family the feature introduced — flags, field names, struct
  fields, extensions, fixtures — and sweep once per family across every
  affected repo.

## Work sizing (W)

- **W1 No human time estimates.** Size work by scope (lines, files,
  subsystems) and risk (well-understood versus exploratory, mechanical versus
  judgment-heavy), leading with whichever dominates.
