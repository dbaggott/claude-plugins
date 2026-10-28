# Issue workflow: answering a spec review

Part of the `issue-workflow` skill. Read this when a reviewer is reviewing your
issue bodies as specs, posting a verdict per issue per round with findings you
answer. `references/creating.md` covers writing a body in the first place; the
reviewer's side is the `issue-reviewer` skill.

This is not the review of the PRs that resolve an issue — those arrive as PR
reviews and are answered through `git-workflow`'s `references/review-rounds.md`.

## Handing the issue to its reviewer

The session that wrote the body for review — filed the tracking issue, or
decomposed one into a set — is its author for the review and answers every
round. `<URL>` below is the issue's, or for a set the parent's, since the
reviewer takes in its children. Ask with `AskUserQuestion`: "Who runs the spec
review?"

1. **"Spawn the reviewer (Recommended)"**: "A reviewer subagent reviews the
   issue from GitHub, and this session answers its rounds as they come back.
   You can't talk to the reviewer directly."
2. **"My own session"**: "You start the reviewer in a new session with one
   prompt, and can talk to it there. This session watches for its rounds and
   answers them."

Without `AskUserQuestion`, ask per `references/delegated.md`.

### Spawn the reviewer

On **"Spawn the reviewer"**, dispatch `issue-reviewer` as
`dnbg-workflow:reviewer-orchestrated`, in the background, with the prompt
`Review <URL> as a spec.` and nothing else but its draft directory line
(`git-workflow`'s "Draft files"): the reviewer judges the body alone, not this
session's view of it. Each round reaches you as its report, which ends
on its own wait for your answer, so answer it per "Answering" and arm no watch.
A report that is not a round — a `Delegated question:` it posted, or a failure
to start, such as no `reviewer-setup` — goes to the operator, and an answer goes
back to the reviewer with `SendMessage`. When it ends, give the operator the
retrospective path its final report names, asking for one first if it names
none, as "Asking the agents for one" in
`<skill-dir>/../process-review/references/retrospective.md` says.

### My own session

On **"My own session"**, in one turn, in this order:

1. Read each issue's `updated_at` (`gh api repos/<owner>/<repo>/issues/<n> --jq
   .updated_at`), for the issue or the parent and every child of a set, and keep
   the latest. No reviewer has acted yet, so it stands in for the first-arm
   rule's noted time, and it is not earlier than your own last body edit.
2. Tell the operator, in these words: "Start the reviewer in a **new** session:
   `review <URL> as a spec`. Leave this session open: it answers the reviewer's
   findings, and it is already watching for the first round, so there is
   nothing to tell it."
3. Arm the watch in `references/spec-review-wait.md` over the same issues,
   with that `updated_at` as `--since` under the first-arm rule.

### Reaching the review without a hand-over

A session that reaches the review without having handed it over — asked to
answer it cold, or sent here from a pickup — notes the `updated_at` of step 1,
then reads the comments, and goes by the first of these that fits:

- **Every issue's latest verdict is `READY`**: go to "Where it ends".
- **No verdict has been posted**: hand the issue over from the top of
  "Handing the issue to its reviewer".
- **Otherwise**, answer the latest round per "Answering" if it is unanswered,
  then ask whether a reviewer is still running. If one is, wait for it per
  `references/spec-review-wait.md`: from the response after one, as in step 3
  without one. If not, a spawned reviewer having gone with its session, hand
  over from the top.

## What a round looks like

One comment per issue, carrying a verdict — `READY` or `CHANGES REQUESTED` — the
`lastEditedAt` it was reviewed against, and findings with IDs: `<issue>-B<n>`
blocking, `<issue>-O<n>` observations. `CHANGES REQUESTED` means at least one
blocking finding; observations do not block a `READY`.

Check that published `lastEditedAt` against your body's current value. If the body
moved after it, the round straddled an edit and was made against text you have
already replaced — say so rather than answering findings that may no longer apply.

## Answering

**Edit the body first, then comment.** The comment is the receipt for edits
already made. Reversing it makes the reviewer read a body that does not yet carry
what you claimed, and report a fix missing that is not. Both go up as the author
(`SKILL.md`, "Writing as the author"), each drafted in your draft directory
(`git-workflow`'s "Draft files"):

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
  gh issue edit <n> --repo <owner>/<repo> --body-file <body-file>
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
  gh issue comment <n> --repo <owner>/<repo> --body-file <response-file>
```

`<skill-dir>` is this skill's Base directory.

**Respond per finding ID**, dispositioning each one:

- **Fixed** — point at what changed in the body. The reviewer reads the diff, so
  the response need not reproduce it.
- **Rejected, with reasoning** — a legitimate outcome, not a stalling move. A
  reviewer who accepts the reasoning converges on it.

A finding answered with neither is undispositioned, and a round of those is what
halts the review.

Under the "My own session" hand-over, wait for the next round per
`references/spec-review-wait.md` once the response is posted; a spawned
reviewer's report ends on its own wait, so there is nothing to arm.

Once a tracking issue's children are filed, a response that applies a
decision-log row edits each child the row reaches to match first, then the
parent, whose edit changes the entries and sets the row's state to `applied`.

**Do not edit the body again after posting the response.** The body is quiescent
from that moment: the receipt is fixed and the reviewer is reading against it. An
edit you genuinely need afterwards opens a **new round** — make it, then say so in
a fresh comment.

**A fix that edits another issue already at `READY` reopens that issue's round**,
as when a finding on one child is fixed in a sibling. Make the edit and post its
note, with the two commands above on the sibling's number, before the response on the issue that carried the finding, so the response
stays your latest post, and add that issue to the watch. The note names the
finding, by its ID and the URL of the comment carrying it, then the section that
changed, and ends `No blocking findings were open here.`

> Edited "Acceptance criteria" for `281-B2` (<comment URL>). No blocking findings were open here.

## Where it ends

The review converges when every blocking finding is dispositioned and the reviewer
accepts the disposition; the final verdict says so. It can also halt — a round
that disposes nothing new leaves the remainder as an operator decision.

Fold anything the review established that changes what a resolver should build
into the body, per "Maintaining issues" in `SKILL.md`: a fact living only in a
comment is invisible to the handoff.

That end is your close-out, on the author's side. Report the review per
`<skill-dir>/../findings-review/references/report.md`, writing no findings
entries, since a round's observations are settled in the round: Summary names
each issue and its final verdict, and Actionable, at a halt, what is left for
the operator. Write the retrospective per
`<skill-dir>/../process-review/references/retrospective.md`, with `role:
author` and the issue's URL, or the parent's for a set, as `issue:`, as the
report's "At a close-out" says.

Then, once the review has converged, end on the next stage, by the first of
these that fits. Each exit says that GitHub now holds everything the next stage
reads, gives the prompt to paste, and recommends a fresh session for it, since
that stage reads its state from GitHub rather than from this conversation. A
tracking issue is one written to `references/tracking-issue.md`'s shape; any
other issue is plain.

- **A set under a tracking issue**, once every issue in it reads `READY`. "The
  set is `READY`. In a fresh session: `orchestrate <parent URL>`. This session
  has nothing further to do."
- **A plain issue.** "Ready to pick up. In a fresh session: `resolve <URL>`, or
  `orchestrate <URL>` to have an author and a reviewer dispatched for you."
- **A tracking issue whose decision log already has its acceptance row.** The
  round re-checked a change, acceptance stands, and no new stage starts here.
- **A tracking issue whose round ran in design mode**, as the round comment's
  first line names. The `READY` covers only the body it was made against, so
  ask only while the body's `lastEditedAt` still matches the round's; a fold
  above that edited the body reopens the review instead. Ask with
  `AskUserQuestion`: "The design review is `READY`. Accept the design?"
  1. **"Accept (Recommended)"**: "Write the acceptance row, then give the
     decomposition prompt."
  2. **"Not yet"**: "Nothing is written. Any edit to the body reopens the
     review."

  On "Accept", write the row `references/tracking-issue.md`'s "Acceptance"
  gives, as a body edit with the first command in "Answering", with the round comment's URL and `operator sign-off in session`, then:
  "Accepted. In a fresh session: `decompose <URL>`." On "Not yet", write
  nothing, and ask what the operator still wants to change. Without
  `AskUserQuestion`, post the question as a `Delegated question:` per
  `references/delegated.md` and stop; the row an accepting answer writes names
  the URL of the comment carrying it as where the sign-off was given.
- **A tracking issue whose round ran in plain spec mode.** Design mode keys on
  the body's opening line, `This is a **tracking issue**`, which it lacked when
  reviewed, and acceptance needs a design-mode `READY`, so offer no picker. Say
  so; once the body starts with that line (an edit, which reopens the review),
  hand it to a reviewer again per "Handing the issue to its reviewer".
