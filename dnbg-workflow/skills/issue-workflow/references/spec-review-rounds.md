# Issue workflow: answering a spec review

Part of the `issue-workflow` skill. Read this when a reviewer is reviewing your
issue bodies as specs, posting a verdict per issue per round with findings you
answer. `references/creating.md` covers writing a body in the first place; the
reviewer's side is the `issue-reviewer` skill.

This is not the review of the PRs that resolve an issue — those arrive as PR
reviews and are answered through `git-workflow`'s `references/review-rounds.md`.

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
what you claimed, and report a fix missing that is not.

**Respond per finding ID**, dispositioning each one:

- **Fixed** — point at what changed in the body. The reviewer reads the diff, so
  the response need not reproduce it.
- **Rejected, with reasoning** — a legitimate outcome, not a stalling move. A
  reviewer who accepts the reasoning converges on it.

A finding answered with neither is undispositioned, and a round of those is what
halts the review.

**Do not edit the body again after posting the response.** The body is quiescent
from that moment: the receipt is fixed and the reviewer is reading against it. An
edit you genuinely need afterwards opens a **new round** — make it, then say so in
a fresh comment.

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
stamp wakes it on your own round.

Dispatch on the result:

- **`ACTIVITY`** with `kinds=comment` — the next round landed. Read it.
- **`CLOSED`** — the issue closed rather than converging. Stop.
- **`IDLE`** — the deadline elapsed. Re-arm; after a second empty window, tell the
  operator nothing has landed rather than waiting silently.
- **`ERROR`** — the watch could not see the issue, whatever the reason. **Do not
  re-arm**, and do not report that the reviewer has not answered: you do not know
  that. `reason=issue-query` points at auth or the issue numbers;
  `issue-query-shape` means the payload stopped parsing, so auth will look fine;
  `bad-args` and `unsupported-forge` mean it never started.

**Re-arm from the `── re-arm ──` line the watch prints, never from the clock.** It
carries `since` set to that run's own `now`; activity is counted against `since`,
so anything landing between one run returning and the next starting is filtered
out for good rather than deferred.

**A dead watch is not a quiet review.** The watch lives in this session, so a
background task returning no result line at all — killed, session ended, reloaded
— is blindness rather than silence, and looks identical to a round nobody has
posted. Re-read the issues' comments before concluding the reviewer has gone quiet.

## Where it ends

The review converges when every blocking finding is dispositioned and the reviewer
accepts the disposition; the final verdict says so. It can also halt — a round
that disposes nothing new leaves the remainder as an operator decision.

Fold anything the review established that changes what a resolver should build
into the body, per "Maintaining issues" in `SKILL.md`: a fact living only in a
comment is invisible to the handoff. Picking the issue up is then
`references/resolving.md`.
