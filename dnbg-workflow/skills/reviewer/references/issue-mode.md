# Reviewer: issue-scoped mode

Part of the `reviewer` skill. Read this only when you are assigned as the reviewer
for an **issue** rather than for a single PR; `SKILL.md` carries the per-PR flow
that this mode reuses once it has a PR in hand. This file runs through the first
discovery pass; `references/issue-mode-wait.md` carries the discovery loop and the
wait, and a tracking issue continues in `references/issue-mode-tracking.md`.

The operator can assign you as **the reviewer for an issue** rather than for a
single PR — "you review issue 74", "be the reviewer on <issue URL>". It works
whether or not any PR exists yet: assigned early, you wait for the work to
arrive; assigned late, you pick up whatever is already open.

What changes is the standard you review against. A PR-scoped review judges the
diff on its own terms. An issue-scoped review also asks **whether the issue's
acceptance criteria are met** — a diff can be clean, well-tested, and still not
be the thing the issue asked for. Read the issue body as the spec, and treat an
unmet acceptance criterion as a finding like any other. These are graded
differently:

- **A criterion met by a run** (an eval, a live exercise) is met by a recorded
  run, linked from the PR or the issue and carrying its output. Don't re-run it.
  Fetch the run commit, the head and the base branch, and compare the run's
  tree with the tree that will land:

  ```bash
  git diff --name-only <run commit> \
    $(git merge-tree --write-tree origin/<base-branch> <head>)
  ```

  That one list carries the PR's own commits and whatever the base branch
  gained, however the branch was rebased or merged since the run. Recompute it
  at every grading, since the base branch can move with no commit on the PR. A
  head that conflicts with the base branch has no tree to compare yet, and the
  command fails with `fatal: ambiguous argument`: grade the run once the
  conflict is resolved. A run commit that
  can no longer be fetched is a stale record. The run stands while nothing
  under the paths the criterion names as invalidating it differs. Where the
  criterion also names the behavior the run proves, a file listed under the
  paths leaves the run standing when the author's record shows its change does
  not alter that behavior and the file's diff between the two trees bears that
  out; a file the record says nothing about, or one whose effect on the
  behavior you cannot rule out, voids it. Where the criterion names paths
  alone, any change under them voids it. Where it names no paths, judge from
  the list whether anything the run exercises changed. Say
  which changes you judged and on what basis. No recorded run, or a stale one,
  is a blocking finding naming the run, unless the run is one that waits, as
  below.
- **A run your own blocking findings will void**, because a fix you ask for
  lands under its invalidating paths, is not graded this round. Say in the
  round that the run is expected to be stale once the fixes land, and ask for
  it after them.
- **A run that waits** is an observation naming what it waits on, not a
  blocking finding. It is one of:
  - a criterion blocked only on an operator action outside the PR, such as a
    merge in a test repository or a live exercise only the operator can start;
  - a run the PR description records as `pending (deferred until after the
    first clean round)`, per `issue-workflow`'s `references/resolving.md`;
  - a re-run the PR or its orchestrator has recorded as in progress.

  If nothing else blocks, approve, and say in the verdict that the approval is
  conditional on the run. When the run's record lands, re-verdict on it by the
  rule for a criterion met by a run above, recomputing its comparison then.
  With no commit since the head you approved, the record and that comparison
  are the whole re-review; commits since it get the usual delta review as
  well.

A `## Operator check before review` section is the resolver's stop for the
operator's own look, and a `## Operator steps` section lists what only the
operator can do (`issue-workflow`'s `references/creating.md`). Neither is a
criterion: grade nothing in them.

Honor the same reading discipline the body's own labels set (`issue-workflow`):
"Related (optional — do not read unless blocked)" links stay unread, depth 1
only.

**Reads in issue mode — this file and both siblings — run under your own auth,
and every write runs as the bot.** Each write is one command behind
`"<skill-dir>/../../scripts/as-role.sh" reviewer <repo> --`, which puts the bot's
token in place for that command alone, so nothing is left live for a later read
to pick up. The reads keep your auth because the issue and its timeline are the
operator's, and no read needs the bot. There are two writes: the assignment
comment below, and the project review's link in
`references/issue-mode-tracking.md`.

**Record the assignment, but do not claim the issue.** Setting an assignee or an
`assigned:*` label marks the issue as *being implemented* — `issue-workflow`'s
pickup check reads those as "someone is already on it" and stops a coder from
starting. A reviewer must not produce that signal. Leave a comment instead,
unless one is already there: a replacement reviewer inherits its predecessor's
assignment, and one comment records it.

```bash
gh issue view <n> --repo <repo> --json comments --jq \
  '[.comments[].body | select(startswith("Claude Code is acting as reviewer on this issue."))] | length'
# post only when that printed 0
"<skill-dir>/../../scripts/as-role.sh" reviewer <repo> -- \
  gh api repos/<repo>/issues/<n>/comments \
  -f body="Claude Code is acting as reviewer on this issue." --jq .created_at
```

**This step also fixes the first issue wait's `since`**
(`references/issue-mode-wait.md`), from whichever path it took:

- **Posted:** the `created_at` the post printed. It stands in for the
  first-arm rule's stamp noted before the action: your own comment falls at
  `since` and drops out, under the bot's login or the operator's.
- **Skipped, because the check printed more than 0:** the `now=` of a
  `fetch-issue-set.sh` call made after the check. The inherited comment's own
  time would wake the wait on everything since the original assignment.
- **The post failed:** the `now=` of a `fetch-issue-set.sh` call made after
  the failure.

On those two paths, the snapshot below is that call when it ran after the check
or the failure; when it ran before them, run it once more.

**Then snapshot its sub-issues**, since an issue that has them is reviewed
differently:

```bash
"<skill-dir>/../../scripts/fetch-issue-set.sh" <owner>/<repo> <n> \
  --json-out=<draft directory>/issue-set.json
```

The set goes to that file, for `jq` to read, and stdout is the result line
alone. `children: []` means a plain issue: the rest of this file and
`references/issue-mode-wait.md` apply. Any children make it a tracking issue: go
to `references/issue-mode-tracking.md`, which reuses the discovery here, the wait
and the per-PR review. A
`result=ERROR` is neither: the set was not read, so say so rather than reviewing
it as a plain issue.

**Find the PRs that resolve it.** One script, three sources. Each misses
something the others catch, and the gaps are not hypothetical — a real pair (a
PR closing an issue in one repo, its infrastructure sibling in another) is found
by exactly one of the first two:

```bash
"<skill-dir>/../../scripts/pr-sources.sh" <owner>/<repo> <n>
```

It prints the deduped union as one `<url> relevance=… state=…` line per PR, then
`result=OK count=<n> closing=… search=… timeline=…`. `state=` is the PR's own
(`OPEN`, `MERGED` or `CLOSED`), so filter on it rather than reading each PR
again; `unknown` means the script could not read the PR, so count it as
possibly open.

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
each open one, reading `state` with it on a `state=unknown` one, and hold the
drafts back. Draft status is the author's signal that the work
is not yet endorsed for review — `git-workflow` covers why it opens PRs that way.
A verdict on a draft spends the attention that signal is asking you to withhold,
and a `--request-changes` leaves threads the author has to resolve on work still
in progress.

This applies to the **discovered** set only — hold these back without asking. A
draft the operator *names* gets the picker in `SKILL.md`'s "If the PR is a draft,
ask before reviewing".

Watch a held-back draft rather than dropping it, arming the ready check, in the
background with `timeout: 7200000` as `SKILL.md`'s watch is:

```bash
"<skill-dir>/../../scripts/watch-pr.sh" <owner>/<repo> <n> <last_head> <since_iso> <slug> \
  --role=reviewer --was-draft --round-dir=<draft directory>
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

The URLs are full URLs rather than numbers, which is what makes the multi-repo
case work at all: a number collides across repos and a URL does not. Once you
have one member of a set, `gh search prs --owner <owner> head:<branch>` returns
the rest, since `git-workflow` pairs siblings by branch name. **Review the whole
set, not the first PR you find** — a change split across an infra PR and an app
PR is only correct as a pair, and each half read alone looks incomplete or
unmotivated.

**Then read `references/issue-mode-wait.md` before reviewing anything** — one
discovery pass is never the whole assignment.
