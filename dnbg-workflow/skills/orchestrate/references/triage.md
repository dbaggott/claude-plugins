# Orchestrate: triage and the decision log

Part of the `orchestrate` skill. Read this before answering the first question
an author asks; `SKILL.md` says when one arrives.

## What you may decide alone

Escalate by default. Answer a question yourself only when the answer is one of
these, and the issue's recorded rationale covers the case at hand rather than
merely mentioning it:

- **(a)** applying a decision whose recorded rationale names the case at hand,
  whether it is in the issue body, in its parent's body, or in an earlier
  `Decision log:` row on the issue;
- **(b)** choosing among options the design already ranks, or taking the default
  an open question states;
- **(c)** an implementation choice that changes no interface, contract,
  user-visible behavior, or acceptance criterion;
- **(d)** ordering and scheduling of work;
- **(e)** a question of fact about the tree or the forge's state, answered by
  checking it;
- **(f)** how to meet a criterion only a main session can run, such as an
  orchestration or a run on skill text the branch changes. You run it, in this
  session, and the author records the run on the PR from what the forge shows;
  the reviewer grades the record. Before starting, ask the operator for their
  part, such as the merges, in one message. The run uses the branch's skill
  text: read the changed files from the author's worktree in place of the
  installed copies, and the author's record says it ran that way. A branch
  that changes a script, a hook, or a skill a dispatched subagent loads needs
  a fresh session loading the branch instead, which you launch yourself, per
  "Run a branch-loaded session" below.

Everything else escalates, and these always do: a change to an external
contract or to user-visible behavior, a change of scope, a choice between
competing values, and anything that contradicts the design. So does a discovery
the issue's author could not have known about, because answering it is a new
decision rather than a lookup.

When the issue is a child of a tracking issue whose decisions state an
escalation allowlist of their own, that decision is the authority instead, and
a difference between the two is itself an escalation.

## Run a branch-loaded session

Launch it as a background Bash task, from a local clone of the repository the
run targets, with the prompt in a quoted heredoc so the shell expands nothing
in it:

```bash
cd <clone> && env -u CLAUDE_CODE_SESSION_ID claude -p --verbose \
  --output-format stream-json --session-id <uuid> --setting-sources "" \
  --permission-mode <mode> --plugin-dir <worktree>/<plugin> \
  > <log> 2>&1 <<'PROMPT'
<prompt>
PROMPT
```

- **`env -u CLAUDE_CODE_SESSION_ID`** keeps your session id out of the run, which
  would otherwise claim issues as you and read your claims as its own.
- **`<uuid>`** comes from `uuidgen`, so you hold the id to resume it by.
- **`--setting-sources ""`** keeps the installed copy of the plugin out, so the
  run loads the branch's and nothing else's. It drops every user-scope setting
  and plugin with it, so a criterion that needs one, such as `dnbg-practices`,
  adds that plugin with another `--plugin-dir`.
- **`<mode>`** is your own session's permission mode, since a headless session
  cannot answer a prompt. If yours is not `bypassPermissions`, ask the operator
  which mode the run gets in (f)'s one message.
- **`<log>`** is a file from `mktemp` in your scratchpad. Its `system` `init`
  line lists the plugin at the worktree path with source `<plugin>@inline`; the
  author's record cites that line as the evidence the run loaded the branch.

The operator's part stays their usual one, the merges. Hand them the command
and the prompt instead only when you have no Bash tool, or when they ask to run
it themselves.

**When the session exits early.** A print session ends once its main turn has
nothing left to wait on, which can be any wait on a subagent, and its subagents'
watches end with it. Its exit wakes you. Read what it was waiting on from the
log's final `result` line, and the PR's state from the forge:

- **An event the forge already shows**, such as an approval at head while it
  waits on the merge handoff: resume at once.
- **The merge:** relay the handoff, and resume once the operator says the PR
  merged and the forge confirms it.
- **An event not yet on the forge:** tell the operator what it waits on, and
  resume when they say it has happened.

Resume with the same flags, a prompt naming the event and the subagents to
reach, and the log appended to:

```bash
cd <clone> && env -u CLAUDE_CODE_SESSION_ID claude -p --verbose \
  --output-format stream-json --resume <uuid> --setting-sources "" \
  --permission-mode <mode> --plugin-dir <worktree>/<plugin> \
  >> <log> 2>&1 <<'PROMPT'
<prompt>
PROMPT
```

Such as "<PR URL> is approved at head. SendMessage your author by its agent id
for its merge handoff, then relay it", or after the merge "<PR URL> merged.
SendMessage your author and reviewer by their agent ids to finish, then Stop."
A resumed session can exit again; resume it each time until the log ends on its
Stop report.

**Evidence about processes.** The author's record comes from the forge and the
`init` line. When a criterion is about processes, such as no `<script>` spawned
by role X, start a second background task beside the run that appends
`ps -axo pid,ppid,command` to a scratchpad file every few seconds and ends when
the run's process does. Attribute each process by its arguments, the target
repository and issue, never by a bare `pgrep`: other sessions on this machine
run the same scripts. The samples go to the author for its record.

## The row

Every answer, escalation outcome, and application of a prior decision is one
comment on the issue. Its first line is fixed, so a scan can grep for it:

```
Decision log: <ID> — <state>
```

- **`<ID>`** is the decision the row records or applies. Cite an existing ID
  when there is one: a `D#` or `Q#` the issue or its parent defines, or the ID
  of an earlier row. A plain issue's sections carry no IDs, so a row applying
  one cites its heading, as in `Decision log: Proposed approach — applied`. A
  new decision takes the next unused `<n>-D<k>` on this
  issue, where `<n>` is the issue number, so it cannot collide with the parent's
  own IDs.
- **`<state>`** is `proposed` for a question escalated and not yet answered,
  `decided` for an answer given, and `applied` for an existing decision applied
  to a new case.

Below the first line, in this order:

- **Question** — the `Delegated question:` comment's URL, or the operator
  comment's URL when the decision came from one.
- **Answer** — the answer, in a sentence or two.
- **Basis** — the allowlist item it was decided under and the rationale it rests
  on, quoted or linked; or `operator`, with how they answered (in session, or
  the comment's URL).

A row under (a) names the decision it applies:

```
Decision log: D4 — applied

**Question:** https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>
**Answer:** Leave the parent's body to the orchestrator; propose the change in your report.
**Basis:** allowlist (a). D4's rationale, "body edits are whole-body replaces and two writers clobber each other", names this case.
```

Under a tracking issue, each row is also a row of the parent's decision-log
table, per `references/multi-issue.md`.

An escalation gets two rows: `proposed` when you ask, and `decided` with the
operator's answer when it arrives. A restart reads a `proposed` row with nothing
after it as a question still waiting on the operator.

## Promote decided rows into the body

After a `decided` row, the issue body changes so a cold reader of it sees the
decision without the log: the section the decision affects, such as the
"Proposed approach" or an acceptance criterion, changes and links the row.

On the issue whose question the row answers, the author makes that edit, never
you: the message carrying the answer tells it to, and a row decided before
dispatch goes in the dispatch prompt instead.
An `applied`
row changes nothing in the body, since the decision it applies is already there.
