# Orchestrate: a tracking issue's children

Part of the `orchestrate` skill. Read this when step 1 of `SKILL.md`'s "On
start" finds sub-issues. The parent's body is the design, in the shape
`issue-workflow`'s `references/tracking-issue.md` gives it, and each child is
driven by `SKILL.md`'s single-issue flow, changed only where this file says.

`<slug>` is the reviewer bot's login, the `login=` of
`"<skill-dir>/../../scripts/as-role.sh" --login reviewer <owner>/<repo>`.

## On start

1. **Claim the parent**, as `SKILL.md`'s step 2 claims an issue. A `FOREIGN`
   claim held by a session is the predecessor orchestrator, and the operator's
   answer about it covers every child it claimed.
2. **Take over the in-flight children**: the open ones carrying a claim, which
   are the ready set's `waiting` entries whose `reasons` include `claimed` (the
   loop's step 3, run now). Run `claim-issue.sh` on each. `OWN` is yours.
   `FOREIGN` with the predecessor's id is re-claimed with `--as=orchestrator
   --claim` once the operator has said the predecessor is gone. Any other holder is not part of
   this run: leave the child alone, and it waits like a blocker outside the
   project. For each child you hold, run `SKILL.md`'s steps 3 to 5 on it, then
   dispatch a fresh author, and a reviewer when its PR is out of draft, per
   `SKILL.md`'s "Dispatch the author, then the reviewer".
3. **Read the parent's log**: its decision-log table, and any
   `Decision log: archived rows` comment. Read every comment on the parent
   newer than the last row for decisions the operator gave there, then collect
   every child's rows ("Collect the children's rows"). A `proposed` row is an
   escalation still waiting, and a `decided` row is work to finish before any
   dispatch (`references/design-change.md`).
4. **Review the design.** Read the parent's body as `SKILL.md`'s step 5 reads
   an issue, then run `issue-workflow`'s critical review on it: the parent is
   yours, not an author's, and a design you believe is wrong is an escalation
   before any dispatch.
5. **Run the loop.** With every child already closed, the loop goes straight
   to the closeout, whose step 1 continues a predecessor's closeout PR. A parent already closed by that PR's merge has
   only "Stop" left.

## The loop

Run it after start and after every event that can change the answer: a child
closing, a child leaving flight (below), a row reaching `applied`, a spec
verdict on a child. On a child closing, first collect that child's rows (below).

1. **Finish every `decided` row not yet `applied`**, per
   `references/design-change.md`.
2. **Scan for systemic problems** (below).
3. **Read the ready set:**

   ```bash
   "<skill-dir>/../../scripts/ready-set.sh" <owner>/<repo> <parent> --slug=<slug>
   ```

   `ready` is what may be dispatched, in the parent's order. `waiting` gives each
   held child's `reasons`: `blocked` (with the `blocked_by` URLs, which include
   a blocker closed as not planned), `claimed`, and, when `parent.spec_review`
   is true, `no-ready-verdict` or `design-not-ready`, the parent's own latest
   verdict not reading `READY`. A
   `result=ERROR` (`bad-args`, `unsupported-forge`, `not-found`, `issue-query`,
   `issue-query-shape`, or `set-overflow`) means the set was not read: dispatch
   nothing, say so, and stop.
4. **`open=0`**: every child is closed. Once every child's agents have ended,
   resolve the parent through its closeout PR, per `references/closeout.md`.
5. **Dispatch** while fewer than three children are in flight, or the cap the
   operator set: take the next `ready` child, skipping any that a `decided` row
   still being applied reaches, or whose blocker is still in flight, since its
   body may yet need that blocker's merge sweep. Claim it first, with
   `claim-issue.sh <owner>/<repo> <child> --as=orchestrator --claim` and the
   same `--label` and
   `--stamp` as any claim. The claim is what keeps the next ready set from
   offering the child again, so a child whose claim did not return `result=OK`
   is not dispatched. Then run `SKILL.md`'s steps 3 to 5 on it and dispatch its
   author with `SKILL.md`'s recipe.
6. **Nothing in flight, nothing ready, and no `decided` row still being
   applied** means the run cannot progress: a cycle, a blocker outside the
   project, or a child held for a verdict or by someone else. Report each open
   child with its `reasons` and blockers, and stop. While a row is still being
   applied, its re-review's verdict reaches you as the `issue-reviewer`'s
   report, so wait for it.

A child is **in flight** while it is open and `claim-issue.sh` reads `OWN` on
it, or closed, until its author's final report and its reviewer's
`**Reviewer close-out: assignment ended**` are in. Then apply the sweep its
author's final report carries (below), collect both agents' close-outs, and
fold the run's findings into the parent (`references/findings-fold.md`). A
child that closes without a merged PR: tell the operator.

## Waiting

`SKILL.md`'s "Wait on subagent reports", across every agent in flight, plus
the reports of the `issue-reviewer` agents you dispatch
(`references/design-change.md`, section 4) and the replies of the bookkeeping
subagents (below). A spec or set review verdict on a
child is that agent's report: run the loop, and handle a `CHANGES REQUESTED`
from a re-review in `references/design-change.md`. The closeout PR's review is
handled from the PR, per `references/closeout.md`.

Keep, per child, what its author's last report said it is waiting for, when the
report ends on a wait rather than a question or a result. Several authors can
be waiting at once, and that record is what
https://github.com/dbaggott/claude-plugins/issues/260's resume rule reads.

## Triage and the log

Triage against the parent's body first, its decisions with their rationale,
then the child's own body. `references/triage.md`'s allowlist applies, and a
decision the parent's log already holds, in its table or its archived rows, is
applied, citing its row.

Every row is written twice, as the `Decision log:` comment on the child and a
row of the parent's decision-log table linking it, by one call:
`references/triage.md`'s `decision-row.sh` call with `--parent=<parent URL>`.
Its `parent-` reasons are `log-row.sh`'s below; re-run the same call.

A decision raised on the parent, such as an operator comment or a systemic
finding, has only the table row, and reaches a child through
`references/design-change.md`, which promotes it into the child's body. Append
it with:

```bash
"<skill-dir>/../../scripts/log-row.sh" <owner>/<repo> <parent> --table="Decision log" \
  --row='| <date> | <ID> | <child URL or —> | <entry> | <state> |' --as=orchestrator
```

`result=OK` means the row is in the body. A re-run never adds it twice, so on
`write-lost`, `write` or `issue-query` run it once more, and escalate if it
fails again. `section-missing` or `table-missing` means the parent has no
decision log to append to, which is an escalation.

Every `decided` row, an answer to one child's question included, is finished
through `references/design-change.md`, whose last step marks it `applied`.
A row of the operator check before review (`references/triage.md`, "The row")
whose feedback changes no design section has nothing to sweep: set it `applied`
as `design-change.md`'s step 6 does, and post the one-line note it gives for a
row already in the body.

You are the parent body's only writer. A child's body is its author's, per
`SKILL.md`; you edit one only in a design change's sweep of a child not yet
dispatched (`references/design-change.md`), or in a merge's sweep of a child no
one holds (below). Any other
body edit is reading the body, changing it, and writing it back with the body
edit in `SKILL.md`'s "Write as the orchestrator", re-read just before each
write. A sweep's edit of a child's body is the same.

**An escalation** waits on the operator. With `AskUserQuestion`, ask with it:
the loop pauses until they answer, and the events that arrived meanwhile are
handled after. Without it, post the question on the parent per
`issue-workflow`'s `references/delegated.md`, with the comment command in
`SKILL.md`'s "Write as the orchestrator", and end the turn with it as your
report, on your closing line, **Your move:**, naming its comment URL. Only the
child that asked waits; the rest of the loop keeps moving as reports arrive.
The operator's answer is a comment on the parent: at each loop while the
question is open, read the parent's comments newer than it. With no
agent left in flight to wake you, the turn you ended is the run's end, and a
restart reads the answer under "On start". An answer is a `decided` row, then
`references/design-change.md`.

## The bookkeeping steps

Collecting the children's rows, a merge's sweep of its siblings, and the scan
for systemic problems each read material whose conclusion fits in a line.

What you read stays in your context, re-sent on every later wake, and a
subagent starts at about 36K tokens of its own, so a step runs in one where its
reads are larger than that or would otherwise sit through many later wakes:

- **Collecting rows**: in a subagent when it reads more than three children;
  inline otherwise.
- **A sibling sweep**: in a subagent when it reaches more than one sibling;
  inline for one.
- **The cross-child scan**: always in a subagent.

Dispatch it with the Agent tool, in the background, as `general-purpose`, with
no `model` and the step's prompt below. Fill each `<…>` but the `<its …>`
ones, which the subagent takes from each URL, and give `<scripts>` as the
absolute path of `<skill-dir>/../../scripts`, since the subagent loads no
skill. The sweep, the one that drafts bodies, also gets a draft directory,
from `mktemp -d <scratchpad>/bookkeeping-<parent>.XXXXXX`. It ends its turn
on its reply: a result line, then one line per item. You act on the reply and stay the one who decides: every
question, escalation, row other than the step's own, and message to an author
is yours. A reply not in the step's format, or a subagent that died, means the
step runs inline, re-reading what the subagent may already have written: the
table, a sibling's body, and the comments of a sibling someone else holds, for
one already naming the PR's URL.

A step out in a subagent is not done until you have acted on its reply: on
start, run the loop only once the rows are collected; the loop dispatches
nothing while a scan is out; and a child whose sweep is out stays in flight.
While rows are being collected, edit the parent's body only through
`log-row.sh` or `decision-row.sh`, which re-check their writes. Before a
restart, wait for every reply rather than stopping the subagent.

## Collect the children's rows

A child worked outside this run has its rows only as its own `Decision log:`
comments. Take the children from `fetch-issue-set.sh`, run as
`references/design-change.md` step 2 runs it. Inline, for each child:

1. Read its comments with
   `gh api --paginate repos/<child owner>/<child repo>/issues/<child>/comments`,
   all three taken from the child's URL, since a child can live in another
   repo. Keep those whose first line starts with `Decision log: `. Never read
   the parent's this way: that prefix opens other comments there.
2. Append each one whose URL neither the table nor an archived-rows comment
   links, with `log-row.sh` as above:
   `| <date> | <ID> | <child URL> | <answer> (<comment URL>) | <state> |`.
   `<date>` is today's, not the comment's: the table is newest row last. The
   ID and state are its first line's, and the answer its **Answer**, with each
   `|` escaped as `\|`.

Then handle each new row as "On start" step 3 does. In a subagent:

> You copy decision rows from the children of `<parent URL>` into its
> decision-log table. Write only the rows this prompt names, ask no one, and
> send no message to any agent.
> 1. Read the parent's body with `gh issue view <parent> --repo <owner>/<repo>
>    --json body`, and its comments with `gh api --paginate
>    repos/<owner>/<repo>/issues/<parent>/comments`, keeping those opening
>    `Decision log: archived rows`.
> 2. For each child below, read its comments with `gh api --paginate
>    repos/<its owner>/<its repo>/issues/<its number>/comments`, all three
>    taken from the child's URL. Keep those whose first line starts with
>    `Decision log: ` and whose URL neither the body nor an archived-rows
>    comment links.
> 3. Append each, oldest first, with `<scripts>/log-row.sh <owner>/<repo>
>    <parent> --table="Decision log" --row='| <today> | <ID> | <child URL> |
>    <answer> (<comment URL>) | <state> |' --as=orchestrator`. The ID and state are the comment's first line's, the answer
>    its **Answer**, with each `|` escaped as `\|`. On `write-lost`, `write` or
>    `issue-query`, run it once more.
>
> Reply with `rows=<n appended> body_chars=<last value log-row.sh printed, or
> none>`, then a line `new <ID> <state> <comment URL>` for each row appended,
> and a line `failed <comment URL> <reason>` for each row not appended.
> Children: `<child URLs>`

Handle each `new` row as "On start" step 3 does, run "Keep the log under the
body limit" on `body_chars`, and append each `failed` row inline, escalating
when it fails again.

## A merge's sweep of its siblings

A child's author's final report names each open sibling its merge's issue
sweep reached, with the items in that sibling's body its merge shipped. This
replaces `SKILL.md`'s "Stop" for that sweep. Mark each item shipped, with the
PR's URL, as `issue-workflow`'s "Maintaining issues" does, by who holds the
sibling:

- **No one** — edit its body yourself, as the orchestrator.
- **Its author in this run** — `SendMessage` it the PR's URL and the items to
  mark shipped in its body.
- **Anyone else** — comment them on it, as that section does for an issue
  someone else has claimed, with the comment command in `SKILL.md`'s
  "Write as the orchestrator".

Marking shipped work changes no design, so it takes no log row and no
re-review. In a subagent:

> You mark shipped, with `<PR URL>`, the items its merge shipped in the open
> siblings below. Edit no body this prompt does not send you to, write no
> decision row, ask no one, and send no message to any agent. Every write runs
> as `<scripts>/as-role.sh orchestrator <its owner>/<its repo> -- <command>`,
> from a non-empty body file in your draft directory, deleted once posted.
> For each sibling, run `<scripts>/claim-issue.sh <its owner>/<its repo> <its
> number> --as=orchestrator`, all three taken from its URL:
> - `UNCLAIMED`: read its body, mark each item shipped with the PR's URL, and
>   write it back with `gh issue edit <its number> --repo <its owner>/<its
>   repo> --body-file <file>`, re-reading the body just before the write.
> - `FOREIGN`: comment the items and the PR's URL on it with `gh issue comment
>   <its number> --repo <its owner>/<its repo> --body-file <file>`, for its
>   holder to fold in.
> - `OWN`: change nothing; this run's author holds it.
>
> Reply with `swept=<sibling URLs edited or commented, or none>`, then a line
> `notify=<sibling URL>:<items>` for each `OWN` sibling, and a line `failed
> <sibling URL> <reason>` for each write whose command exited non-zero.
> Siblings and their items: `<from the author's final report>`
> Your draft directory: `<path>`

`SendMessage` each `notify=` item to that sibling's author, with the PR's URL.
A `notify=` sibling with no author in flight is held by your claim alone: edit
its body yourself. Sweep each `failed` sibling inline.

## Systemic problems

Scan the parent's log at each loop, and each review round on a child's PR as
its reviewer's report brings it. Raise a finding when:

- questions from two different children cite the same `R#` or `D#`;
- one decision has been `applied` more than three times, or the parent's `Q5`
  threshold if it sets one;
- a reviewer finding recurs on a second child's PR, meaning the same `R#` or
  `D#` is cited, or the same file and the same kind of finding.

The first two are read from the log, inline. The third, the cross-child scan,
runs for a round with findings once another child has a PR, in a subagent,
which reads the rounds from GitHub: paste none of the rounds you hold into its
prompt.

> You look for review findings that recur across the PRs of one tracking
> issue's children. Read only: write nothing, ask no one, and send no message
> to any agent.
> For the new round's PR and each other PR below, read the review bodies and
> the inline review comments, resolved ones included, with `gh api --paginate
> repos/<its owner>/<its repo>/pulls/<its number>/reviews` and `gh api
> --paginate repos/<its owner>/<its repo>/pulls/<its number>/comments`, all
> three taken from each PR's URL. An inline comment's `path` is its file, and its
> `pull_request_review_id` is the review it belongs to.
> A finding in the new round recurs when a finding on another PR cites the same
> `R#` or `D#`, or is on the same `path` and is the same kind of finding.
> Reply with `systemic=none`, or `systemic=<n>` followed by a line `recurs <new
> finding URL> <other finding URL> <the R#, D# or path> <the kind, in a few
> words>` for each.
> The new round: review `<review URL>` on `<PR URL>`.
> The other PRs: `<PR URLs>`

Each finding, from the log or the
scan, is a parent-table row, `proposed`, naming the IDs and the children
involved, plus a findings entry (`SKILL.md`), and it escalates like any
question. A pattern already in a row is not raised again.

## Keep the log under the body limit

After each write to the parent, if its body passes 50,000 characters, which
`log-row.sh` prints as `body_chars`, move every table row whose child is closed
and whose state is final into one comment opening `Decision log: archived
rows`, and leave one row in its place pointing at that comment. Both writes are
`SKILL.md`'s "Write as the orchestrator" ones. `proposed` rows and `decided` rows not yet applied stay.

## Stop

Stop when the closeout PR has merged and its post-merge cleanup is done, or
when the operator says to stop after it closed unmerged. Never judge the
end-to-end criteria yourself: the reviewer grades them on that PR. Report under
`SKILL.md`'s three headings, covering every child, with its PR, the closeout PR,
and every escalation with its outcome.
