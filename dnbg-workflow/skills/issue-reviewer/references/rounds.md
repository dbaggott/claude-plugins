# Issue reviewer: rounds after the first

Part of the `issue-reviewer` skill, covering everything from the author's first
response onwards. `SKILL.md` carries the routing rule, the two passes, and what a
verdict comment contains.

The author obeys the matching half of the ordering and quiescence rules below,
from `issue-workflow`'s `references/spec-review-rounds.md`, which is what lets
each side read the other's state from the issue alone.

## Re-validate before you post — as a gate, not a step

A review is not instantaneous: the body is read, verification runs against the
tree, then the verdict is composed and posted. On an issue under active editing
that gap is long enough for the author to move past what you reviewed.

Before composing the verdict, re-read `lastEditedAt` for every issue in the round
— one aliased query covers the set, the shape `SKILL.md` snapshots with. Then:

- **Unmoved** — post the verdict you composed.
- **Moved** — re-read that body and **recompose its verdict** against the new
  text. It is re-reviewed, not annotated with a note that it moved.

⚠️ **The re-validation must be its own call, and its result read before the
comment is written.** Issuing it alongside the post satisfies the word "before"
and none of its purpose: the answer arrives after the comment has landed, so
nothing was gated. Reading the value is not the gate either — comparing it against
your own read time is.

This narrows the window rather than closing it, since re-validating is never
atomic with posting. The watermark `SKILL.md` has every verdict publish covers the
remainder.

## Read the delta, not the set again

GitHub will not diff issue bodies for you, so the snapshot you recorded is the
only "before" that exists. Take a fresh one each round and diff against the stored
copy rather than re-reading the set cold.

A round reads the **body diff** since your last snapshot and the **response
comment**, per finding ID. Nothing else: a body that did not move and a finding
with no response are both answers.

## Ordering, and what a response means

**The author edits the body, then comments.** The comment is the receipt for edits
already made, so a response claiming a fix the body does not carry means the two
landed out of order — not that the fix is missing.

Check that before reporting a fix absent: compare the issue's `lastEditedAt`
against the response comment's `createdAt`. An edit stamped *after* the comment is
the out-of-order case; say so and re-read, rather than reporting a false "not
fixed" the author has to disprove.

**The body is quiescent once the response comment lands.** An author who edits
again after responding has opened a **new round**, not amended the old one, and
says so in a fresh comment. Otherwise the receipt stays unchanged while the
artifact moves under it.

## Dispositioning, convergence, and the halt

A finding is **dispositioned** when the author has fixed it or rejected it with
reasoning. Both are legitimate: **a rejection you accept is convergence, not a
loss.** One rebuttal each per disagreement — if it still stands after the author's
answer, it goes to the operator rather than to a third exchange.

**Converged** when every blocking finding is dispositioned and you accept the
disposition. Post the final verdict and stop.

**Cap the unproductive rounds, not the total.** A round that disposes findings and
raises new ones from probing the fix is the protocol working, and a flat limit
ends exactly that round. Halt when a round produces no newly-dispositioned
finding, or re-litigates one already settled — then post what remains as needing
an operator decision, say that is what you are doing, and stop. Never an open
loop, and never a halt on a round that was still converging.

## Keeping the issue readable

Rounds accumulate on a body people still have to read. One comment per issue per
round, detail in `<details>`, and at convergence minimize the intermediate rounds
so only the final verdict stays expanded.

`minimizeComment` takes the comment's node id and a classifier, `RESOLVED` being
the one that fits a superseded round; `unminimizeComment` reverses it. The bot may
minimize both its own comments and the author's, which
`IssueComment.viewerCanMinimize` confirms per comment.

```bash
GH_TOKEN="$("<skill-dir>/../reviewer/mint-token.sh")" || exit 1
export GH_TOKEN
gh api graphql -f query='mutation($id: ID!) {
  minimizeComment(input: {subjectId: $id, classifier: RESOLVED}) {
    minimizedComment { isMinimized minimizedReason }
  }
}' -f id=<comment-node-id>
```

## Waiting for the author

Spawn the wait as a **background** task so idle polling never enters the
conversation:

```bash
"<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <n> [n...] \
  --role=reviewer --since="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slug="$(jq -r .slug "${DNBG_REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/reviewer}/config.json")"
```

`--slug` is the login the watch ignores, matched against both `<slug>` and
`<slug>[bot]`; passing the bot's is what stops your own round waking you. Watching
the whole set costs one call per tick, so waiting on every issue you were handed
is no more expensive than waiting on one.

Dispatch on the result — **including `ERROR`, which must not fall to the
catch-all**:

- **`ACTIVITY`** — `kinds=` says what landed. `comment` is a response to read;
  `body-edit` without a comment is the new round the quiescence rule above says
  the author still owes a comment on. `edited=` carries each issue's body-edit
  stamp, so the ordering check costs no extra call.
- **`CLOSED`** — the issue was closed rather than answered. Say so and stop.
- **`IDLE`** — the deadline elapsed. Re-arm; after a second empty window, tell the
  operator nothing has landed rather than waiting silently.
- **`ERROR reason=issue-query`** — the watch could not see the issue. **Do not
  re-arm**, and do **not** report that the author has not responded: you do not
  know that. Check `gh auth status` and that the numbers resolve, then tell the
  operator.
- **`ERROR reason=issue-query-shape`** — the query answered but the payload
  stopped parsing, so auth will look fine. Check the payload.
- **`ERROR reason=bad-args`** / **`unsupported-forge`** — the watch never started.
  Fix the arguments, or accept the forge, and re-spawn.

`missing=<n,…>` on any result names numbers that resolve to no issue — a typo, a
transfer, or a PR number. Say so rather than reporting those issues as quiet.

**A dead watch is not a quiet issue.** The watch lives in this session, so a
background task returning no result line at all — killed, session ended, reloaded
— is blindness rather than silence, and it looks identical to a round nobody has
answered. Re-read every watched issue's state and `lastEditedAt` and diff against
your last snapshot before concluding anything.

## When the watch is unavailable: the manual relay

Without a watcher the protocol still runs, with the operator carrying the wake:
you post the round and report that findings are up, the operator prompts the
author, and the operator tells you to look again. Verdicts, finding IDs, ordering,
delta reads and convergence are unchanged, because all of them live on the issue
rather than in either session.

**Re-read the bodies when prompted rather than trusting the relay** — a relayed
summary is the "author claims fixed" case the ordering check exists for, one step
further removed.

This is the degraded mode: it costs an operator turn per round, and cannot run
unattended at all.
