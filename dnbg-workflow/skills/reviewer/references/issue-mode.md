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
bot's** — prefix each with `env -u GH_TOKEN`. The reviewer App requests
`pull_requests`, `contents`, `checks` and `metadata` and **no `issues` scope at
all** (`reviewer-setup/bootstrap.py`), so a bot token cannot touch a genuine
issue: `gh api repos/<repo>/issues/<n>` answers `403 Resource not accessible by
integration`, and `gh issue view` fails to resolve it. `pull_requests: write`
covers conversation comments on a *PR*, which is a different resource — that's
what makes this look like it should work. Same reasoning, and same fix, as
**Resolving inline findings** in `SKILL.md`. What it guards is a call that mints
a bot token and then touches the issue: `SKILL.md` has every `gh` write mint in
its own tool call, so the token is only ever live inside one. The prefix costs
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

**Find the PRs that resolve it.** One script, three sources. Each misses
something the others catch, and the gaps are not hypothetical — a real pair (a
PR closing an issue in one repo, its infrastructure sibling in another) is found
by exactly one of the first two:

```bash
"<skill-dir>/../../scripts/pr-sources.sh" <owner>/<repo> <n>
```

It prints the deduped union as one URL per line, then
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
"<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <n> <last_head> <since_iso> <slug> --was-draft
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
"<skill-dir>/../../scripts/watch-pr.sh" --issue [--exclude=<url,url,...>] \
  <owner>/<repo> <n> "" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(jq -r .slug "${DNBG_REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/reviewer}/config.json")"
```

**At most one issue wait at a time, re-armed only on its own return.** A PR
watcher returning is a trigger to re-discover, not to arm a second wait — two
waits on one issue each paginate the whole timeline every tick and both report
the same `CLOSED`.

The same script the PR watch uses, in `--issue` mode — so this wait gets the same
backoff curve and the same failure counting rather than its own. It returns
`ACTIVITY` when a linked PR appears, `CLOSED` if the issue closes, `IDLE` on
timeout, and `ERROR reason=issue-view` / `ERROR reason=issue-timeline` when one of
its two sources keeps failing.

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
adding it. `tests/coupling.bats` pins these sources against `watch-pr.sh`'s, so a
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

- **`ACTIVITY`** — references listed. Back to step 2.
- **`CLOSED`** — the work was dropped or resolved without a PR. Say so and stop.
- **`ERROR reason=issue-view`** — the watch could not see the issue. **Do not
  re-arm**, and do **not** report that nothing has landed: you do not know that.
  Expired auth or a wrong issue number produce exactly this. Check `gh auth
  status` and that the issue number resolves, then tell the operator.
- **`ERROR reason=issue-timeline`** / **`issue-timeline-shape`** — same remedy,
  narrower cause: the issue was visible but its timeline was not, so the watch was
  blind to precisely the mention-only PRs source 2 exists to catch. **Do not
  re-arm** and do not report a quiet issue — a partial blindness reported as quiet
  is the failure the two-source wait was built to remove. The `-shape` variant means
  the endpoint answered but the payload stopped parsing, which is a schema change
  rather than an outage: `gh auth status` will look fine, so check the payload.
- **`IDLE`** — the deadline elapsed with nothing. Re-arm (carrying the exclusion
  list forward), and after the second empty window tell the operator nothing has
  landed rather than waiting silently. Both sources ran, so this genuinely means no
  PR references the issue — **don't reach for "the issue number is probably wrong"
  as the explanation**.

The `ERROR` branch is the whole point of using the shared script here. Routing it
into the `IDLE` catch-all would re-arm into the same failure and then state
something false about the issue — a report that nothing has landed, made by a
watch that never saw it.

Per PR, run `SKILL.md`: mint a token, review, post, and watch.
