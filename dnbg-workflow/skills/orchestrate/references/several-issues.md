# Orchestrate: several issues with no parent

Part of the `orchestrate` skill. Read this when you are asked to orchestrate
more than one issue and they share no tracking issue; a tracking issue's
children are `references/multi-issue.md`'s. The issues are one of two cases,
which the request says, or else the issue bodies do: each resolved by its own
PR, or the set resolved together by one PR. When neither says, ask the operator
which.

Both cases share these:

- **An escalation holds only the issue it came from**, as `references/multi-issue.md`'s
  "An escalation" says for a child: the other agents' reports are handled as
  they arrive.
- **"Restart on schedule" counts this session's wakes across every issue**,
  waits until every author in flight has a PR open or is waiting on the
  operator, and tells the operator to start the fresh session on every issue
  URL still open, naming the case.

## Independent issues

Each issue is its own run of `SKILL.md`'s flow, from this one session: its own
claim, its own decision-log rows on its own issue, its own author and reviewer,
its own close-outs, yours included, and its own "Stop", less the report,
which comes once for the session. A tracking issue among them runs
`references/multi-issue.md`'s loop as its run.

- **Order by overlapping files.** Before dispatching an issue's author, compare
  the files its body names with those named by every issue in flight. While
  one in flight names a file this one does, hold this one until that one's
  run stops, so its author starts from a default branch that carries any merge.
  Otherwise take them in the order the operator gave.
- **At most three in flight**, or the cap the operator set, as under a tracking
  issue. An issue is in flight from its dispatch until its "Stop".

Report once every run has stopped, under "Stop"'s three headings, with each
issue's PR, escalations and agents' close-outs under its URL.

## A set resolved by one PR

One run drives the set, with these changes to `SKILL.md`'s flow:

- **On start, run steps 1 to 5 on every issue.** An issue with children cannot
  join a set: ask the operator whether to drive it on its own. An open PR that
  step 3 reads as `closes` or `sibling` on any issue is the set's PR; two
  different ones, or only a `mention`, go to the operator as step 3 says.
- **Operator steps** are asked once for every issue together, as under a
  tracking issue. An operator check before review declared on any issue makes
  the dispatch line's check phrase, carrying each issue's recipe.
- **One author**, dispatched with the recipe's first line naming every issue:

  > Resolve `<issue URL>`, `<issue URL>`, … together in one PR whose
  > description closes each of them, send it to review when you're done, and
  > auto-handle any reviewer feedback. The issues are already claimed under
  > your session id. Post each question on the issue it concerns.

  The recipe's bracketed lines follow as for one issue, each naming the issue
  it came from.
- **One reviewer**, dispatched with:

  > Act as the reviewer on `<issue URL>`, `<issue URL>`, …, one set resolved
  > by one PR, in `reviewer`'s issue mode. Post the assignment comment on each
  > issue, discover PRs from every issue, grade the PR against every issue's
  > acceptance criteria, keep at most one issue wait, over the issues still
  > open, and end once every issue is closed and no PR on any of them is open.

- **Retrospectives**, the agents' and yours, are named for the set
  (`<skill-dir>/../process-review/references/retrospective.md`).
- **Rows go on the issue each decision affects**, triaged against that issue's
  body; a decision affecting several gets its row on each.
- **Stop** reports the one PR, with each issue's URL and its escalations under
  it.
