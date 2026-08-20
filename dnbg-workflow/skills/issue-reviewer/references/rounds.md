# Issue reviewer: rounds after the first

Part of the `issue-reviewer` skill. `SKILL.md` carries the routing rule, the two
passes, and what a verdict comment contains; this file carries everything from the
author's first response onwards.

The author's side of the same protocol is `issue-workflow`'s
`references/spec-review-rounds.md`. Both sides obey the ordering and quiescence
rules below, which is what lets each read the other's state from the issue alone.

## Re-validate before you post — as a gate, not a step

A review is not instantaneous. The body is read, then verification runs against
the tree, then the verdict is composed and posted, and on an issue under active
editing that gap is long enough for the author to move past what you reviewed.

Before composing the verdict, re-read `lastEditedAt` for every issue in the round
— one aliased query covers the whole set, the same shape `SKILL.md` takes the
snapshot with. Then:

- **Unmoved** — post the verdict you composed.
- **Moved** — re-read that body and **recompose its verdict** against the new
  text. An issue whose body moved is re-reviewed, not annotated with a note that
  it moved.

⚠️ **The re-validation must be its own call, and its result read before the
comment is written.** Issuing it alongside the post satisfies the word "before"
and none of its purpose: the answer arrives after the comment has landed, so
nothing was gated. Holding the disproving evidence is not the same as acting on
it — a `lastEditedAt` read during verification and quoted in a finding still
gates nothing unless it is compared against your own read time.

Even gated, this narrows the window rather than closing it, because re-validating
is never atomic with posting. That is why the verdict publishes the
`lastEditedAt` it was reviewed against (`SKILL.md`): the watermark makes a
straddled round detectable afterwards by anyone, where the check has to win a race
to help at all.

## Read the delta, not the set again

Every round after the first is read against the snapshot the last one took.
GitHub will not diff issue bodies for you, so the snapshot you recorded is the
only "before" that exists — take a fresh one each round, and diff the new body
against the stored copy rather than re-reading the whole set cold.

What a round reads:

- The **body diff** since your last snapshot.
- The **response comment**, per finding ID.
- Nothing else. A body that did not move and a finding with no response are both
  answers.

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
says so in a fresh comment. Without that rule the receipt stays unchanged while
the artifact moves under it, and a review in progress is reviewing text nobody
will admit to.

## Dispositioning, convergence, and the halt

A finding is **dispositioned** when the author has either fixed it or rejected it
with reasoning. Both are legitimate outcomes: **a rejection you accept is
convergence, not a loss.** One rebuttal each per disagreement — state the
disagreement once, and if it stands after the author's answer, it goes to the
operator rather than to a third exchange.

**Converged** when every blocking finding is dispositioned and you accept the
disposition. Post the final verdict and stop.

**Cap the unproductive rounds, not the total.** A round that disposes findings
and raises new ones from probing the fix is the protocol working — a flat round
limit ends exactly that round, which is the most productive kind. Halt when a
round produces no newly-dispositioned finding, or re-litigates one already
settled. Then post what remains as needing an operator decision, say that is what
you are doing, and stop.

Never an open loop, and never a halt on a round that was still converging.

## Keeping the issue readable

Rounds accumulate on a body people still have to read.

- One comment per issue per round, never one per finding.
- Detail folded into `<details>`.
- At convergence, minimize the intermediate rounds so only the final verdict
  stays expanded.

`minimizeComment` takes the comment's node id and a classifier; `RESOLVED` is the
one that fits a superseded round. `unminimizeComment` reverses it, and
`IssueComment.viewerCanMinimize` says whether the identity you hold may do it —
the bot can minimize both its own comments and the author's.

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

`--slug` is the login the watch ignores, matched exactly against both `<slug>` and
`<slug>[bot]`. Passing the bot's slug is what stops your own round from waking
you.

It wakes on a comment, a body edit, or the issue closing, and names which fired on
which issue. Watching the whole set costs one call per tick, so waiting on every
issue you were handed is no more expensive than waiting on one.

Dispatch on the result — **including `ERROR`, which must not fall to the
catch-all**:

- **`ACTIVITY`** — `kinds=` says what landed. `comment` is a response to read;
  `body-edit` without a comment is an edit that has not been claimed yet, which
  the quiescence rule above says is a new round the author still owes a comment
  on. `edited=` carries each issue's body-edit stamp, so the ordering check costs
  no extra call.
- **`CLOSED`** — the issue was closed rather than answered. Say so and stop.
- **`IDLE`** — the deadline elapsed with nothing. Re-arm; after a second empty
  window, tell the operator nothing has landed rather than waiting silently.
- **`ERROR reason=issue-query`** — the watch could not see the issue. **Do not
  re-arm**, and do **not** report that the author has not responded: you do not
  know that. Check `gh auth status` and that the numbers resolve, then tell the
  operator.
- **`ERROR reason=issue-query-shape`** — the query answered but the payload
  stopped parsing, so auth will look fine. Check the payload.
- **`ERROR reason=bad-args`** / **`unsupported-forge`** — the watch refused to
  start. Nothing is blind: fix the arguments, or accept the forge, and re-spawn.

`missing=<n,…>` on any result names numbers that resolve to no issue — a typo, a
transfer, or a PR number. Say so rather than reporting those issues as quiet.

**A dead watch is not a quiet issue.** The watch lives in this session. If the
background task returns no result line at all — killed, session ended, reloaded —
that is blindness, not silence, and it looks identical to a round nobody has
answered yet. Re-read every watched issue's state and `lastEditedAt` from GitHub
and diff against your last snapshot before concluding anything about where the
round stands.

## When the watch is unavailable: the manual relay

Without a watcher, the protocol still runs with the operator carrying the wake
between the two sides. Only the wake changes:

- You post the round and tell the operator findings are up.
- The operator prompts the author, who responds per finding ID on the issues.
- The operator tells you to look again.

Verdicts, finding IDs, the body-before-comment ordering, delta reads and
convergence are unchanged, because all of them live on the issue rather than in
either session.

**Re-read the bodies when prompted rather than trusting the relay.** A relayed
summary is the "author claims fixed" case the ordering check exists for, one step
further removed — the operator is reporting what the author said, not what the
body says.

This is the degraded mode: it costs an operator turn per round, and it cannot run
unattended at all.
