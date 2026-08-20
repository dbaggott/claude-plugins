# Issue workflow: answering a spec review

Part of the `issue-workflow` skill. Read this when an independent reviewer is
reviewing your issue **bodies** as specs — posting a verdict per issue per round
with findings you answer — and you are the author of those bodies.

`references/creating.md` covers writing a body in the first place; this covers the
rounds after someone reviews one. The reviewer's side is the `issue-reviewer`
skill, and the ordering and quiescence rules below are the half of its protocol
you own.

This is not the review of the PRs that resolve an issue. Those arrive as PR
reviews and are answered through `git-workflow`'s `references/review-rounds.md`.

## What a round looks like

The reviewer posts one comment per issue per round. It carries a verdict —
`READY` or `CHANGES REQUESTED` — the `lastEditedAt` the review was made against,
and findings with IDs: `<issue>-B<n>` blocking, `<issue>-O<n>` observations.

`CHANGES REQUESTED` means at least one blocking finding. Observations do not block
a `READY`.

Check the published `lastEditedAt` against your body's current value. If the body
moved after the timestamp the verdict names, the round straddled an edit and was
made against text you have already replaced — say so in your response rather than
answering findings that may no longer apply.

## Answering

**Edit the body first, then comment.** The comment is the receipt for edits
already made. Reversing it makes the reviewer read a body that does not yet carry
what you claimed, and report a false "not fixed" you then have to disprove.

**Respond per finding ID**, and give each one a disposition:

- **Fixed** — say what changed in the body. The reviewer reads the diff, so the
  response points at the change rather than reproducing it.
- **Rejected, with reasoning** — a legitimate outcome, not a stalling move. A
  reviewer who accepts the reasoning converges on it.

A finding you answer with neither is undispositioned, and an entire round of those
is what halts the review.

**Do not edit the body again after posting the response.** The body is quiescent
from that moment: the receipt is fixed, and the reviewer is reading against it. An
edit you genuinely need afterwards opens a **new round** rather than amending the
old one — make it, then say so in a fresh comment, so the reviewer knows the
artifact moved out from under the receipt.

## Waiting for the next round

Spawn the wait as a **background** task so idle polling never enters the
conversation:

```bash
"<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <n> [n...] \
  --role=author --since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

`--role=author` resolves the ignored login from `gh api user` when no `--slug` is
given, so the watch ignores your own comments and wakes on the reviewer's. Arm it
*after* posting the response — `--since` is stamped at arm time, so an earlier
stamp wakes the watch on your own round.

Dispatch on the result:

- **`ACTIVITY`** with `kinds=comment` — the next round landed. Read it.
- **`CLOSED`** — the issue closed rather than converging. Stop.
- **`IDLE`** — the deadline elapsed. Re-arm; after a second empty window, tell the
  operator nothing has landed rather than waiting silently.
- **`ERROR`** — the watch could not see the issue, whatever the reason. **Do not
  re-arm**, and do not report that the reviewer has not answered: you do not know
  that. `reason=issue-query` points at auth or the issue numbers;
  `reason=issue-query-shape` means the payload stopped parsing, so auth will look
  fine. `bad-args` and `unsupported-forge` mean it never started.

**A dead watch is not a quiet review.** The watch lives in this session, so a
background task that returns no result line at all — killed, session ended,
reloaded — is blindness rather than silence, and it looks identical to a round
nobody has posted yet. Re-read the issues' comments from GitHub before concluding
the reviewer has gone quiet.

## Where it ends

The review converges when every blocking finding is dispositioned and the reviewer
accepts the disposition; the final verdict says so. It can also halt — a round
that disposes nothing new leaves the remainder as an operator decision, and the
reviewer says that is what it is doing.

Either way the issue is then in the state the review existed to produce, and
picking it up is `references/resolving.md`.

**The comments are the record.** What the review established lives on the issues,
so a resolver reading them cold gets the reasoning. Fold anything that changes
what the resolver should build into the **body** — per "Maintaining issues" in
`SKILL.md`, a fact that lives only in a comment is invisible to the handoff.
