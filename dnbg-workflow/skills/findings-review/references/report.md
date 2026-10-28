# Findings review: the report

Part of the `findings-review` skill. Every role reads this when it writes its
report, the one carrying Summary, Observations and Actionable: the author at its
merge handoff and once its PR merges or closes, the PR reviewer at its handoff
when it approves and at its close-out, both sides of a spec review where it ends, the orchestrator at Stop. The
site that sends you here says what each heading holds for your role; the rules
are here.

`<skill-dir>` is the Base directory of the skill that sent you here.

## The three headings

Report under exactly these three headings, in this order. **Print all three
every time; an empty one says so in a few words**: an omitted section reads as
"nothing there" and "never considered" alike.

- **Summary**: what happened, with the PR or issue by full URL. Self-contained:
  the operator may have read nothing since handing the work over.
- **Observations**: informational, and nothing for the operator to do.
- **Actionable**: one line each, naming the concrete next step and where.

**Actionable is the narrow section, and doubt resolves toward Observations**:
it is the one the operator is invited to skim. An item earns Actionable only by
naming a concrete next step and where. One you already judged as not worth
raising during the cycle does not earn it here: passing it on hands over the
work without the judgement that would let the operator size it. Out of scope is
what qualifies a deferral, not merely having decided against it. A clean cycle
routinely leaves the section empty.

A finding raised in a comment, by the other role or anyone else, that was
neither acted on nor listed elsewhere in the report goes under Observations or
Actionable.

Unless the site says it writes none, write each finding as a findings entry per
`<skill-dir>/../findings-review/references/entry.md`, which says which items get
one, and name the entry's path on the item's line. Beyond writing those
entries, don't act on the list: filing and fixing are the operator's call.

## The closing line

Unless you are a dispatched agent, end every turn that leaves the next move to
the operator, report or not, on a closing line, printed last, after Actionable
and any Retrospective. It takes one of two leads:

- **`**Your move:**`** followed by the action and what this session does
  meanwhile, such as "watching for the merge", with the action's URL or, in a
  fenced block beneath the line, its command, even when either appears above.
- **`**Done:**`** followed by "nothing is running; this session can be closed",
  or by each watcher, subagent or background task still running and what ends
  it.

A turn ending on an `AskUserQuestion` picker needs no closing line: the picker
is the move, and it notifies on its own.

On a Your move, also call the harness's notification tool where it has one, in
Claude Code `PushNotification`, loading it first if it is deferred. Send one
line under 200 characters with no markdown, leading with the action, such as
`PR 570 approved — ready to merge`. A "not sent" result means the operator is at
the terminal and already sees the turn; it is not an error. A Done notifies only
at `orchestrate`'s Stop, which ends a run long enough that the operator has
likely left.

A dispatched agent, any subagent whose turns end in a report to the session
that dispatched it, writes no closing line and sends no notification.
The session that passes its report on adds them.

## A report after a handoff

Where you already gave this report on the same PR, as the author does at its
merge handoff, a later report is a delta against it, under the same three
headings in the same order. Under each heading put only what arrived after the
handoff, such as a late comment, a conflict, or a check that went red and was
fixed; a new item gets its findings entry as above. Where a heading has nothing
new, say "nothing new since the handoff" rather than repeating it: a second
copy of the report is the one that drifts from the first.

Where you have no handoff report to measure against, because this session never
gave one or it is no longer in your context, give the full report.

## At a close-out

A role's close-out is the end of its part of the work, which its skill names.
There, answer the retrospective prompt in
`<skill-dir>/../process-review/references/retrospective.md`; its "When a
retrospective is written" says whether that becomes a file, named in a
**Retrospective** section ending the report, or lines under Observations. A
report at any other moment, such as the author's merge handoff, carries
neither.
