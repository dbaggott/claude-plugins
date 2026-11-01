# Reviewer: re-reviewing a PR you already reviewed

Part of the `reviewer` skill. `references/watch.md` and `SKILL.md`'s
"Responding to comments and replies" route here; `SKILL.md` carries the first
pass.

When asked to re-review a PR your bot already reviewed — new commits were pushed,
the author asks for another look, or the last blocker under your
`--request-changes` was answered without a commit — post a fresh review. The
verdict is keyed to the current HEAD, whether or not it moved.

**Take the round in one call** — the delta diff, whatever landed in
conversation, your standing verdict, and every unresolved thread. On a wake the
watcher has already made this call and names its output on the `── round ──`
line: read that file. When it prints a `── next ──` line instead, the fetch
failed: run that, arguments filled in, rather than composing it:

```bash
"<skill-dir>/../../scripts/pr-round.sh" <owner>/<repo> <n> <last-reviewed-sha> <since_iso> <slug>
```

Those are the values you already track for the watcher, so the input is on hand.
It prints `── diff ──`, `── activity ──` and `── threads ──` sections, then one
result line carrying `verdict`, `verdict_sha`, `at_head`, `reviewed_after_head`
and a `_src` status per source. Pass `""` for the SHA on a first review; that
asks for the full diff.

The diff is the **delta** (`diff=delta`) wherever a prior SHA exists and the
base has not moved under it: exactly the changes your last verdict didn't cover,
rather than the whole PR again. `diff=none` means HEAD
hasn't moved since you handled it, which is the normal answer on an `ACTIVITY`
wake, including the answered-last-blocker trigger, and costs no request at all.
It is not a failed fetch.

`diff=same-tree` means HEAD moved onto exactly the tree your last verdict saw: a
rebase that only moved the base, such as dropping a squash-merged parent's
commits. The diff section is empty because the compare would show the new base's
changes as the PR's. What is left to check is that the base did not move under
the tree: read the PR's full diff against its new base (`gh pr diff <n> --repo
<owner>/<repo>`) and confirm every hunk is one you have reviewed. A base change
the tree lacks shows up there as a hunk the PR now reverts, possibly inside a
file you already reviewed, so a file list does not catch it. With that clean,
re-verdict under the rules below, naming both SHAs ("Re-approving at `1a2b3c4`:
same tree as `9f8e7d6`"). Under `--request-changes` the findings are no more
addressed than before, which is the no-op-substance case below.

`diff=interdiff` means HEAD's merge base with the PR's base ref moved since you
handled it, as a merge from base or a rebase moves it, and the tree changed. The
delta would carry every base commit in between as the PR's, so the section holds
the PR's own change instead: for each file whose added or removed lines, status
or rename source differ from what you last reviewed, a diff of the two patches,
labeled `(last reviewed)` and `(now)`, each opening with a `status:` line. Each
line's first character is the interdiff's and the second the patch's, so `++` is
a line the PR now adds that it did not before, and `-+` one it no longer adds.
Hunk headers read `@@ @@` with their line numbers stripped, and context lines are
shown but not compared: a base commit near the PR's hunks rewrites both without
changing the work. A file absent from the section has the same change you
reviewed. An empty
section is the base moving under unchanged work, which is the no-op-substance
case below. Review the files it lists, conflict resolutions included, as the
delta.

An empty section means "nothing there" only where its `_src` reads `ok`; `fail`
or `shape` means that source went blind, which is not a quiet round.

- **Prior verdict `--approve`**: **re-post a verdict whenever HEAD has moved past
  the SHA your standing approval is attached to** — `--approve` if the new diff is
  still clean, `--request-changes` if it introduces issues. Even when your verdict
  is unchanged, and including no-op-substance pushes (whitespace, formatter,
  merge-from-base). **Name the SHA in the body** ("Re-approving at `1a2b3c4`").

  The trigger is the SHA mismatch, not whether the change was substantive.
  Judging substantive-ness is what fails here:
  the author cannot distinguish silence-because-trivial from
  silence-because-the-reviewer-is-gone, so both read as a reviewer who might still
  speak, and their watcher waits for a signal you decided not to send.

  It also moves the *record*, not just the conversation. A review carries a
  `commit_id`, and GitHub renders a stale approval in the merge box with no
  caveat — one green check over "read the new commits and is fine", "hasn't looked
  yet", and "no verdict is ever coming". A fresh verdict re-attaches `commit_id`
  to the current HEAD, so "is HEAD approved?" becomes answerable from the API by
  the author, a human merger, or a later session, without asking anyone.

  **Review the delta before re-approving.** This rule invites rubber-stamping,
  which is worse than the silence it replaces: silence is merely uninformative,
  while a verdict nobody stood behind is confidently wrong and gets merged on.

- Whether GitHub dismissed the approval on the push does not enter into it. Under
  the rule above you re-verdict either way, so the repo's *Dismiss stale pull
  request approvals* setting changes no behaviour of yours — don't read branch
  protection to decide this (it needs **admin** and answers 403/404 on write-only
  access, so the branch was unreliable as well as unnecessary). Where stale
  dismissal genuinely bites, GitHub already forces the re-approval and this rule
  is a no-op; it only fires in the ambiguous case.
- **Prior verdict `--request-changes`**: the PR stays blocked until a fresh
  review lands (a top-level comment doesn't dismiss it). `--approve` if the new
  diff fixes the findings; `--request-changes` again if not. If the new commits
  are no-op substance that didn't address the findings, leave it — the PR stays
  correctly blocked. On the unmoved-HEAD trigger there is no new diff: a finding
  answered without a commit — a description fix you have checked
  (`gh pr view <n> --json body`), or a rebuttal you accepted — counts as fixed,
  so the verdict is `--approve` when nothing else blocks.

"Has HEAD moved past my verdict?" is answered by the packet's own `at_head` and
`reviewed_after_head`, which are `pr-verdict.sh`'s answer carried through — the same question the
author's side asks as "is HEAD approved?", which is the point of keeping the
record current. Outside a round, ask it directly:

```bash
"<skill-dir>/../../scripts/pr-verdict.sh" <owner>/<repo> <n>
```

Your verdict is current iff the result line reads `at_head=1 reviewed_after_head=1`.
The script takes the last **verdict**, not the last approval — an `APPROVED`
followed by a `CHANGES_REQUESTED` on the same SHA is not an approval, and
`COMMENTED` (what a thread reply posts) is not a verdict at all.
`reviewed_after_head` is the third condition because a force-push re-anchors an
existing review onto the rewritten commit, leaving `at_head=1` over a tree you
never saw — re-review it. That is invisible to a **resumed or fresh session**,
which has no `LAST_HEAD` baseline to catch the push with.
`tests/pr-verdict.bats` pins all three. `result=ERROR`, and `unknown` in that
field, both mean the check could not see — not that your verdict is stale.

Where approvals are **required**, `reviewDecision` answers "is HEAD approved?"
directly and is the primary source — it handles supersession and multiple
reviewers, which this comparison does not. This is the answer where no approval
is required, and it is the only one there: `reviewDecision` is `null`, and
neither the merge box nor `dismiss_stale_reviews` fills the gap.

Alongside the fresh review, **resolve any inline thread whose concern is now
answered** — `SKILL.md`'s "Resolving inline findings" carries the mechanics.
