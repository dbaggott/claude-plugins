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
unmet acceptance criterion as a finding like any other. Two kinds are graded
differently:

- **A criterion met by a run** (an eval, a live exercise) is met by a recorded
  run, linked from the PR or the issue and carrying its output. Don't re-run it.
  It stands while nothing under the paths the criterion names as invalidating it
  changed after the run's commit; list what changed with
  `gh api repos/<repo>/compare/<run commit>...<head> --jq '.files[].filename'`.
  Where the criterion names no paths, judge from that list whether anything the
  run exercises changed, and say which paths you judged by. No recorded run, or
  a stale one, is a blocking finding naming the run.
- **A criterion blocked only on an operator action** outside the PR, such as a
  merge in a test repository or a live exercise only the operator can start, is
  an observation naming that action, not a blocking finding. Approve, and say
  in the verdict that the approval is conditional on it.

Honor the same reading discipline the body's own labels set (`issue-workflow`):
"Related (optional — do not read unless blocked)" links stay unread, depth 1
only.

**Every `gh issue` command in issue mode — this file and both siblings — runs under your own auth, not the
bot's** — prefix each with `env -u GH_TOKEN`. The bot reviews; the issue itself
is the operator's, and the only bot write to one is the project review's link
in `references/issue-mode-tracking.md`, which posts through `gh api`. What the prefix
guards is a call that mints a bot token and then touches the issue: `SKILL.md`
has every `gh` write mint in its own tool call, so the token is only ever live
inside one. The prefix costs
nothing in the calls where none was minted, and is what saves the ones where one
was. `gh search prs` is unaffected — it works under either identity.

The `scripts/` helpers this file calls clear `GH_TOKEN` themselves, so the
prefix is only ever needed on the bare `gh issue` commands in issue mode.

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

`children: []` means a plain issue: the rest of this file and
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

**Then read `references/issue-mode-wait.md` before reviewing anything** — one
discovery pass is never the whole assignment.
