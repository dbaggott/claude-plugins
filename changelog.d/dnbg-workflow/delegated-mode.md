Skills now know what to do when they need an answer and nobody can give one. An
agent without `AskUserQuestion`, as in any subagent, posts the question as a
comment opening with `Delegated question:` on the issue it is working (or the PR,
when there is no issue) and ends its turn with the question as its report. It no
longer improvises or picks silently. An answer the dispatcher gave in advance,
such as "send it to review when done", is used instead of asking.

This replaces the "unattended" branches, which keyed on what the operator had
said rather than on anything an agent can detect. The reviewer no longer takes
"wait until ready" on a draft, and `issue-reviewer` no longer takes the spec
review on an ambiguous request, without being told to.
