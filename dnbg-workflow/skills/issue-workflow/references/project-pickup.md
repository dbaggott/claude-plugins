# Issue workflow: an issue that belongs to a project

Part of the `issue-workflow` skill. Read this at pickup, after reading the
claim and before making one: `references/claiming.md` sends you here when you
resolve an issue, and `orchestrate`'s "On start" when you orchestrate one. Skip
it when `claim-issue.sh` read `OWN`: an orchestrator claimed the issue for its
author, and working it on its own is that author's dispatch.

```bash
"<skill-dir>/../../scripts/issue-project.sh" <owner>/<repo> <n>
```

`<skill-dir>` is the Base directory of the skill you loaded. The result line
reads `result=OK parent=<url|none> tracking=<yes|no> children=<count>`.
`result=ERROR` (`bad-args`, `unsupported-forge`, `not-found`, `issue-query`,
or `issue-query-shape`) means the lookup could not see: say so and stop,
claiming nothing.

Each question below is asked once, with `AskUserQuestion`, as a two-option
picker. Without `AskUserQuestion`, post it as a `Delegated question:` per
`references/delegated.md` and stop, claiming nothing.

## A tracking issue you were asked to resolve

At `tracking=yes` on "resolve", say that this is a tracking issue and that
resolving one means orchestrating it, with `orchestrate <URL>`. At
`children=0` it has nothing to orchestrate yet and is decomposed first, which
needs the design accepted: a decision-log row whose Entry opens
`Design accepted:` (`references/tracking-issue.md`, "Acceptance"). With that
row, ask:

1. **"Decompose it now (Recommended)"**: "Load `references/decomposing.md` on
   this URL and continue there."
2. **"Stop"**: "Nothing is claimed."

Without it, say that the design needs a `READY` design review and the
operator's acceptance first, give the prompt `review <URL> as a spec`, for a
reviewer session, and stop, claiming nothing.

At `children` above 0, ask:

1. **"Orchestrate it (Recommended)"**: "Load `orchestrate` on this URL and
   continue there."
2. **"Stop"**: "Nothing is claimed."

## A child of a project

At `parent=<url> tracking=no`, ask "This issue is a child of `<parent URL>`.
Address it on its own, or orchestrate the project?":

1. **"Orchestrate the project (Recommended)"**: "Load `orchestrate` on the
   parent; this issue is dispatched in dependency order with the rest."
2. **"Address this issue on its own"**: "Continue as asked, with this issue's
   own body as the design."

On the first, claim nothing here; `orchestrate` claims the parent and, when the
child is ready, the child. On the second, return to the step that sent you
here.

Otherwise, return to that step without asking.
