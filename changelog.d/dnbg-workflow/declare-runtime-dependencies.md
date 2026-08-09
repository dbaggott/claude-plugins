The plugin now tells you when its enforcement gates are not actually running,
and the README states what the plugin needs to run at all.

**Why this matters.** The two blocking hooks parse their input with `jq` and
resolve repositories with `git`. If either is missing they don't block — they
fail *open*. Claude Code classes a hook exiting non-zero and non-2 as a
non-blocking error, so the edit proceeds, you get a `hook error` notice naming
the missing binary, and **Claude never sees that notice**, leaving the agent to
work as though the worktree and issue gates were live. On a machine without
`jq`, that state was permanent and effectively invisible.

Behavior change, effective as soon as the plugin updates:

- **`inject-rules.sh` now runs a dependency preflight at session start** and
  prints a warning naming the missing binary and what it disables — once per
  session, not once per intercepted tool call. `SessionStart` stdout is added to
  the session context, so the same message reaches you *and* Claude.
- **Missing `jq` and missing `git` are reported differently**, because they
  break different things: without `jq` neither gate can run, while without `git`
  `check-worktree` never fires but `check-issue-create` still gates a
  `--repo`-qualified command.
- **A missing `gh` is reported separately** from the two above — it stops the
  skills working rather than the gates, and one message covering both would
  misstate whichever half you acted on.
- **Nothing new blocks.** The gates keep failing open, and that is deliberate: a
  gate learns which repo an edit targets by parsing its payload, so with no
  parser it cannot tell a covered repo from any other. The only reachable "fail
  closed" would block every edit on the machine, including in projects you never
  listed in `owners`. The silence was the defect, not the fail-open.

The README gains a **Requirements** section listing all six binaries (`jq`,
`git`, `gh`, `python3`, `openssl`, `curl`) with what each is for and what
degrades without it, a documented Claude Code floor of **v2.1.207**, and an
honest platform statement: macOS and Linux are exercised, Windows/Git Bash is
untested and not claimed.
