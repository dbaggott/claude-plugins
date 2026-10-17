Added the `project-status` skill: ask "what's next on <issue URL>" and it says
which stage of the project flow the issue or tracking issue is at, the evidence
for that, and the exact prompt to paste in a fresh session (`review <URL> as a
spec`, `answer the spec review on <URL>` to accept a passed design,
`decompose <URL>`, `orchestrate <URL>`, `resolve <URL>`, or merge the closeout
PR). It only reads; it claims and writes nothing.

The lookup is `scripts/issue-stage.sh`, which prints the stage as one result
line built from the existing claim, project, ready-set and PR-source scripts.
