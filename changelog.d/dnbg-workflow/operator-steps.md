An issue whose work needs something only the operator can do, such as a
browser flow, installing an App or providing a credential, now names it under
`## Operator steps`, and decomposition asks for that section on each child that
needs it. `orchestrate` asks the operator about those steps before dispatching:
once at the start of a tracking-issue run, listing every child's steps together,
or at dispatch for a single issue. The author is told which are already done,
instead of finding out only when it reaches the step.
