# Orchestrate: operator steps

Part of the `orchestrate` skill. Read this before dispatching an author on an
issue whose body has an `## Operator steps` section, and on a tracking issue
before the run's first dispatch when any open child's body has one.

Before dispatching an author, ask the operator about
the issue's `## Operator steps` (`issue-workflow`'s `references/creating.md`)
with `AskUserQuestion`, listing each step with when the work needs it, and two
options: **"Done"**, already done, and **"Not yet"**, the author stops at each
step when it gets there; a split answer comes through "Other". On a tracking
issue, ask once, before the run's first dispatch, re-dispatches on start
included, about every open child's steps together, each under its child's URL,
so a conflict in their order, such as a permission changed before the setup
that needed it, shows before any work. An answer that holds a child until a
step is done holds its dispatch until the operator confirms the step, in a later
row of the same ID. Each answer is a row on its issue,
`Decision log: Operator steps — decided`, with **Question** `none, asked at
dispatch`, the answer, and **Basis** `operator`, in session. The operator's
answer to an author's stop at a step is a later row of the same ID. An issue
that already carries one is not asked again, and the latest row is the answer.
The answer changes no design: it is not promoted into the body, and a tracking
issue's table row for it is written as `applied`, with `--table-state=applied`.
Dispatch does not wait on "Not yet", since most steps are needed late.
