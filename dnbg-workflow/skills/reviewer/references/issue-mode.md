# Reviewer: issue-scoped mode

Part of the `reviewer` skill. Read this only when you are assigned as the reviewer
for an **issue** rather than for a single PR; `SKILL.md` carries the per-PR flow
that this mode reuses once it has a PR in hand.

The operator can assign you as **the reviewer for an issue** rather than for a
single PR — "you review issue 74", "be the reviewer on <issue URL>". It works
whether or not any PR exists yet: assigned early, you wait for the work to
arrive; assigned late, you pick up whatever is already open.

What changes is the standard you review against. A PR-scoped review judges the
diff on its own terms. An issue-scoped review also asks **whether the issue's
acceptance criteria are met** — a diff can be clean, well-tested, and still not
be the thing the issue asked for. Read the issue body as the spec, and treat an
unmet acceptance criterion as a finding like any other. Honor the same reading
discipline the body's own labels set (`issue-workflow`): "Related (optional — do
not read unless blocked)" links stay unread, depth 1 only.

**Every `gh issue` command in this file runs under your own auth, not the
bot's** — prefix each with `env -u GH_TOKEN`. The bot reviews; the issue itself
is the operator's, and the only bot write to one is the project verdict under
"A tracking issue" below, which posts through `gh api`. What the prefix
guards is a call that mints a bot token and then touches the issue: `SKILL.md`
has every `gh` write mint in its own tool call, so the token is only ever live
inside one. The prefix costs
nothing in the calls where none was minted, and is what saves the ones where one
was. `gh search prs` is unaffected — it works under either identity.

The `scripts/` helpers this file calls clear `GH_TOKEN` themselves, so the
prefix is only ever needed on the bare `gh issue` commands below.

**Record the assignment, but do not claim the issue.** Setting an assignee or an
`assigned:*` label marks the issue as *being implemented* — `issue-workflow`'s
pickup check reads those as "someone is already on it" and stops a coder from
starting. A reviewer must not produce that signal. Leave a comment instead:

```bash
env -u GH_TOKEN gh issue comment <n> --repo <repo> \
  --body "Claude Code is acting as reviewer on this issue."
```

**Then snapshot its sub-issues**, since an issue that has them is reviewed
differently:

```bash
"<skill-dir>/../../scripts/fetch-issue-set.sh" <owner>/<repo> <n>
```

`children: []` means a plain issue, and the rest of this file up to "A tracking
issue" applies. Any children make it a tracking issue: skip to that section,
which reuses the discovery and watch below but not the per-PR loop. A
`result=ERROR` is neither: the set was not read, so say so rather than reviewing
it as a plain issue.

**Find the PRs that resolve it.** One script, three sources. Each misses
something the others catch, and the gaps are not hypothetical — a real pair (a
PR closing an issue in one repo, its infrastructure sibling in another) is found
by exactly one of the first two:

```bash
"<skill-dir>/../../scripts/pr-sources.sh" <owner>/<repo> <n>
```

It prints the deduped union as one `<url> relevance=…` line per PR, then
`result=OK count=<n> closing=… search=… timeline=…`.

⚠️ **Read the per-source fields before reporting an empty set.** The union
answers with whatever survived, so one dead source still yields a real — but
narrower — answer. `count=0` with a `fail` among those fields does **not** mean
nothing links the issue; it means the sources that worked found nothing. Saying
"no PRs resolve this" off that is the claim the fields exist to prevent.
`result=ERROR reason=all-sources` is the blind case: nothing was seen at all.

The reasons the three sources are what they are, since the script can carry the
queries but not the judgement:

- **Closing references** list only PRs carrying a closing keyword — the narrowest
  source by construction, and `git-workflow`'s multi-repo rule has exactly one
  sibling close the issue while the rest merely mention it.
- **Timeline cross-references** catch anything that mentions the issue, in any
  repo, keyword or not. Authoritative and immediate — no search-index lag.
- **Text search** is scoped to the **owner, never the repo**: the case this whole
  section exists for is a pair spanning two repos, and `--repo` could only ever
  return siblings in the same one. Over-inclusion (an unrelated repo of the same
  owner mentioning the issue) is the safe direction — judge relevance from the
  PR, don't narrow the query.

**Don't review a discovered PR that is still a draft.** Check `isDraft` on
each and hold the drafts back. Draft status is the author's signal that the work
is not yet endorsed for review — `git-workflow` covers why it opens PRs that way.
A verdict on a draft spends the attention that signal is asking you to withhold,
and a `--request-changes` leaves threads the author has to resolve on work still
in progress.

This applies to the **discovered** set only — hold these back without asking. A
draft the operator *names* gets the picker in `SKILL.md`'s "If the PR is a draft,
ask before reviewing".

Watch a held-back draft rather than dropping it, arming the ready check:

```bash
"<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <n> <last_head> <since_iso> <slug> \
  --role=reviewer --was-draft
```

`<last_head>` is the full 40-character SHA from
`gh pr view <n> --repo <repo> --json headRefOid --jq .headRefOid` — the watcher
refuses anything shorter (`result=ERROR reason=bad-args`). Read it; don't reuse
one you printed for a human.

**All three can only find what the author linked.** A sibling PR whose body
never mentions the issue is invisible to every method here — there is nothing to
discover. `git-workflow`'s "Multi-repo changes" requires that mention for this
reason; if you find a set that looks incomplete, check whether a sibling simply
failed to link, and say so rather than assuming the set is whole.

The URLs carry no PR state — check each with `gh pr view <url> --json state` —
but they *are* full URLs rather than numbers, which is what makes the multi-repo
case work at all: a number collides across repos and a URL does not. Once you
have one member of a set, `gh search prs --owner <owner> head:<branch>` returns
the rest, since `git-workflow` pairs siblings by branch name. **Review the whole
set, not the first PR you find** — a change split across an infra PR and an app
PR is only correct as a pair, and each half read alone looks incomplete or
unmotivated.

⚠️ **Discovery is continuous, not one-shot — the set is never frozen.** The
warning above guards the *spatial* miss (reviewing one PR of a pair). The
*temporal* miss is the likelier one and needs its own guard: siblings are paired
by branch name rather than by when they open (see `git-workflow`, "Multi-repo
changes"), so an infra PR and its app sibling routinely go up hours or days
apart. Discover once and the failure is
worse than missing a PR: the first one merges, you clean up and report the review
complete, and the PR that joins the issue the next day is never looked at. That
is reporting success over half a change.

So the assignment is a loop, not a pass:

1. **Discover** — re-run `pr-sources.sh` above.
2. **Review and watch** every open PR found that you haven't already reviewed.
3. **On every watcher return** — `CLOSED` *or* a re-arm — **discover again** before
   deciding anything. A PR that appeared while you were watching another joins the
   set here. **Skip it while an issue-level wait is armed** — that wait finds
   everything a discovery pass would, and sooner (see the source-3 note below), so
   a PR watcher's return need only handle its own PR. Discover unconditionally
   with no issue wait armed, at any `CLOSED`, and on the issue wait's own
   `ACTIVITY`.
4. **End only when a fresh discovery pass finds no open PR *and* the issue is
   closed.** An open issue with everything merged means more work may still be
   coming; that is not completion.

`gh search prs --owner <owner> head:<branch>` doesn't rescue a one-shot pass
either — it is equally discovery-time, and it only finds siblings sharing a
branch name, so a later follow-up PR on its own branch is invisible to it.

**When discovery finds nothing yet, wait — and load `SKILL.md` step 1's standards
during that wait**, not when the first PR lands: the wait is the one stretch of
the cycle with nothing else in it, and the issue already names the target repo.

Spawn the wait as a **background** task so the idle polling never enters the
conversation:

```bash
"<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <n> [n...] \
  --role=reviewer --since="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slug="$(jq -r .slug "${DNBG_REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/reviewer}/config.json")" \
  [--exclude=<url,url,...>]
```

It wakes on a comment, a body edit, a linked PR appearing, or the issue closing,
and names which of those fired on which issue. Several issues cost one call per
tick, so watching the whole set you were handed is no more expensive than
watching one.


**At most one issue wait at a time, re-armed only on its own return.** A PR
watcher returning is a trigger to re-discover, not to arm a second wait — two
waits on one issue each paginate the whole timeline every tick and both report
the same `CLOSED`.

`watch-issue.sh`, the issue-side sibling of the PR watch — same backoff curve,
same failure counting, same re-arm contract. It returns `ACTIVITY` when a comment,
a body edit or a linked PR lands (`kinds=` says which), `CLOSED` if the issue
closes, `IDLE` on timeout, and `ERROR reason=issue-query` when its query keeps
failing.

**The wait polls sources 1 and 2 above, not source 1 alone.** It has to: source
1 lists only PRs carrying a closing keyword, so a wait built on it is strictly
narrower than the discovery it exists to trigger, and the shape it misses is the
one "Multi-repo changes" *mandates* — exactly one sibling closes the issue, the
rest merely reference it. A real resolving PR that links the issue in prose then
never wakes the watch, and the deadline path below reports it as a probably-wrong
issue number: a diagnosis that cannot be confirmed, because the issue resolves
fine.

Source 3 is deliberately not polled — it is the one source with index lag, so the
timeline already sees everything it would, sooner, and a poll gains nothing by
adding it. `tests/coupling.bats` pins these sources against `fetch-issue-state.sh`'s, so a
fourth one has to be polled or exempted there; its failure message says how.

⚠️ **`--exclude` is what keeps re-arming from spinning, and it must be carried
forward.** A mention-only PR triaged as not-resolving stays open and keeps
satisfying source 2 on every tick, so a wait re-armed without it wakes instantly,
forever. Pass every PR URL already triaged — including ones triaged in earlier
rounds — and add to that list each time you re-arm. Exclusions are full PR URLs,
never bare numbers: source 2 spans repos, where numbers collide.

Excluding a PR is not dismissing it. It means "already looked at, verdict
recorded" — a PR held back as a draft is watched by its own `watch-pr.sh` and
belongs in the exclusion list too, or the issue wait re-wakes for it on every tick
while that watcher is doing the real work.

On return, dispatch on the result — **including `ERROR`, which must not fall to
the catch-all**:

- **`ACTIVITY`** — something landed. `kinds=` says what: `linked-pr` means
  references to triage, so go back to step 2; `comment` or `body-edit` means the
  conversation moved, so read it before deciding whether the assignment changed.
  `edited=` carries each issue's body-edit stamp, so a comment claiming the body
  was updated can be checked without a second call.
- **`CLOSED`** — the work was dropped or resolved without a PR. Say so and stop.
- **`ERROR reason=issue-query`** — the watch could not see the issue. **Do not
  re-arm**, and do **not** report that nothing has landed: you do not know that.
  Expired auth, or every issue number resolving to nothing, produces exactly this.
  Check `gh auth status` and that the numbers resolve, then tell the operator.
- **`ERROR reason=issue-query-shape`** — same remedy, different cause: the query
  answered but the payload stopped parsing, so this is a schema change rather than
  an outage and `gh auth status` will look fine. Check the payload.
- **`ERROR reason=bad-args`** / **`unsupported-forge`** — the watch refused to
  start. Nothing failed and nothing is blind: fix the arguments, or accept that the
  repo is not on a forge this watch supports, and re-spawn.
- **`IDLE`** — the deadline elapsed with nothing. Re-arm (carrying the exclusion
  list forward), and after the second empty window tell the operator nothing has
  landed rather than waiting silently. Both sources ran, so this genuinely means no
  PR references the issue — **don't reach for "the issue number is probably wrong"
  as the explanation**.

**Re-arm from the `── re-arm ──` line the watch prints, never from the clock.** It
carries `since` set to that run's own `now`, and folds in any newly-seen PR;
activity is counted against `since`, so anything landing between one run returning
and the next starting is filtered out for good rather than deferred.

Two fields ride any of those results, and both mean an issue has left the set:

- **`closed=<n,…>`** appears on an `ACTIVITY` line when an issue closed in the
  same wake as activity on the others. Handle the activity *and* report the
  closure — treating the line as activity alone leaves you re-discovering PRs for
  a closed issue. When it was the last watched issue, no re-arm line is printed:
  there is nothing left to watch, so stop.
- **`missing=<n,…>`** names numbers that resolve to no issue — a typo, a
  transfer, or a PR number. Say so rather than assuming those issues are quiet.

The `ERROR` branch is the whole point of using the shared script here. Routing it
into the `IDLE` catch-all would re-arm into the same failure and then state
something false about the issue — a report that nothing has landed, made by a
watch that never saw it.

Per PR, run `SKILL.md`: mint a token, review, post, and watch.

## A tracking issue: whole-project acceptance

A tracking issue's body is a project's design, and its sub-issues carry the work
(`issue-workflow`'s `references/tracking-issue.md`). Each child is reviewed in
its own issue mode. Here you judge whether **the whole was built**, against the
parent's end-to-end acceptance criteria (`A#`), which no child owns and no
per-child review can see. You post no PR reviews in this mode, except on the
closeout PR in step 6.

1. **List the children** from the `fetch-issue-set.sh` snapshot above: each
   one's `url` and `state`. Re-run it on every return of the watch below,
   `IDLE` included, rather than reusing the last one. A sub-issue added or
   reopened produces no watch event of its own, so the snapshot is the only
   place it shows up.
2. **Hold until every child is closed.** While any is open, wait on the parent
   and the open children in one call, so a comment or body edit on the parent
   also reaches you:

   ```bash
   "<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <parent> <open child…> \
     --role=reviewer --since="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --slug=<slug> \
     [--exclude=<url,url,...>]
   ```

   `<slug>` comes from the reviewer config, as in the wait above. Dispatch
   `ERROR`, `IDLE` and `missing=` the same way, and re-arm from the
   `── re-arm ──` line, which carries `--exclude` forward. `CLOSED` and
   `closed=` split by issue here. When they name only children, that is
   progress, not an ending: go back to step 1, and re-arm from the printed line
   only while a child is still open. When they name the parent, the assignment
   ends. A `linked-pr` wake needs no triage here, since each child's PRs are its
   own reviewer's. A child whose URL names another repo of the same owner needs its own watch on that repo,
   because the script watches one repo.
3. **Collect the merged PRs.** Run `pr-sources.sh` once per child, taking
   `<owner>/<repo>` and the number from the child's own `url`, and once on the
   parent. Take the union, reading the per-source fields as described above.
   Check each URL with `gh pr view <url> --json state`. The union is the
   `MERGED` ones. An open PR on a closed child is not part of it, so name that
   PR in the verdict.
4. **Grade every `A#` against that union**, judged on the merged result, not on
   each PR alone. A criterion's `Contributes:` line says which children's PRs to
   read first, but it does not limit what you read. A requirement marked
   `*(end-to-end: A<n>)*` is graded through its `A<n>`. A criterion that needs a
   run, such as an eval or a live exercise, is met by a recorded run: a comment
   or PR section carrying its output, linked from the parent or a child. Don't
   re-run it yourself. If no run is recorded, that is a blocking finding that
   names the missing run.
5. **Post one verdict on the parent**, under the bot identity. The verdict is
   what closeout acts on and what the operator weighs, so it carries the same
   independent identity as `issue-reviewer`'s rounds. Mint the token in the same
   call that posts:

   ```bash
   GH_TOKEN="$("<skill-dir>/mint-token.sh" <owner>)" || exit 1
   export GH_TOKEN
   gh api repos/<repo>/issues/<parent>/comments -F body=@<path> --jq '"\(.user.login) \(.id)"'
   ```

   The printed login must be the bot's. If it is not, the token never arrived
   and the verdict is under the operator's name, where closeout will not find
   it. Delete it with `gh api -X DELETE repos/<repo>/issues/comments/<id>`,
   then fix the mint and post again.

   The body is, in order:

   - `**Project review, round <n>: ACCEPTED**` or
     `**Project review, round <n>: CHANGES REQUESTED**`. Those are the only
     two verdicts.
   - `Graded against body_edited: <value>`, the parent's `body_edited` from the
     snapshot you graded, or `none`. Closeout compares it with the current
     value.
   - The merged-PR union, by URL.
   - **One line per `A#`, every one named**: met, with its evidence (a PR, a
     file at the merged commit, a run's comment), or a finding with the ID
     `<parent>-B<n>`, or `<parent>-O<n>` for an observation. Any blocking
     finding makes the verdict `CHANGES REQUESTED`.
   - The version stamp, under the same condition as a PR review's in
     `SKILL.md`.
6. **Keep watching after the verdict**, with step 2's call on the parent alone,
   and go back to step 1 on every return. Grade a new round when the snapshot
   differs from the one you graded: a child added or reopened, a new merged PR,
   or a parent `body_edited` newer than the one the verdict records. A new
   round re-grades every criterion, not only the ones that failed. A comment
   alone gets a reply when it asks you something, and otherwise a re-arm. After
   `ACCEPTED`, the next PR to link the parent is the closeout PR
   (`orchestrate`'s `references/closeout.md`). Review it per `SKILL.md`,
   asking whether its as-built doc matches the parent body. Closeout edits the
   parent body only when it closes the parent, so that edit never asks for a
   round. The assignment ends when the parent closes.
