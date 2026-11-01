# Orchestrate: an issue still open after its last merge

Part of the `orchestrate` skill. Read this at "Stop" when the issue's state
reads open after the author's final report and the reviewer's close-out on
each PR that report names are in.

Ask the operator with `AskUserQuestion`, "`<issue URL>` is still open after its
last PR merged. Close it?":

1. **"Close it (Recommended)"** — close it (`gh issue close <n> --repo
   <owner>/<repo>`, under `SKILL.md`'s "Write as the orchestrator"). The reviewer's issue
   wait wakes on the close and reaches its end, and Stop continues on that
   report.
2. **"Leave it open"** — tell the reviewer with `SendMessage` that the issue
   stays open, so it ends its assignment. Stop continues on its end report as
   for a closed issue, and your report says the issue is still open.

Without `AskUserQuestion`, an answer your prompt gives settles it, as under `SKILL.md`'s
"Run it as the main session"; otherwise take "Leave it open" rather than
posting the question. Say in the report which you took. Under a tracking issue
each child gets this question, saying that a child left open holds back the
parent's closeout, since the loop reaches it only once every child is closed
(`references/multi-issue.md`).
