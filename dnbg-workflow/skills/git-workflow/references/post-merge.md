# Git workflow: after a merge

Part of the `git-workflow` skill. Read this when a PR merges: the merge watch
reports it, or you are told it merged, including in a session that never
handled a review round.

## After a merge

Any time the operator says something about the merge — kicking it off
("merging", "auto-merge is on", "go ahead") **or asserting it is done**
("merged", "it is merged", "done") — **verify state with `gh pr view` before
acting on the words**. Operators use "merged" for both "the button was clicked,
auto-merge is queued" and "GitHub shows merged"; same phrasing, different states.

```bash
gh pr view <num> --repo <repo> --json state,autoMergeRequest
```

- **`state=MERGED`** — run the cleanup below. If a watch is still in
  flight it will report `CLOSED state=MERGED` shortly; ignore the duplicate
  rather than cleaning up twice.
- **`state=CLOSED`** without a merge — acknowledge, stop, leave the worktree in
  case they reopen.
- **`state=OPEN`, `autoMergeRequest` non-null** — auto-merge is scheduled and a
  running watch will catch it.
- **`state=OPEN`, nothing scheduled** — either they were being forward-looking or
  it has not merged. Say so; don't start a second watch.

Once `state=MERGED` is confirmed (or the merge watch in `references/merge-wait.md` reports `CLOSED state=MERGED`), clean up **before starting any new work**, in this order:

1. Remove the worktree: `git worktree remove .worktrees/<branch-name>`
2. `git switch <default-branch> && git pull --ff-only --prune` — make sure the primary checkout is on the default branch (a no-op given the rule at the top of this skill, but cheap defense in depth against the pull silently fast-forwarding the wrong branch), then fast-forward with the merge commit. `--prune` also clears the remote-tracking branch, if the repo already deleted it on merge.
3. Delete the local branch: `git branch -d <branch-name>`. **On a squash-merge repo this fails**, and that's expected rather than a problem: a squash rewrites the commits, so the feature branch tip is never an ancestor of the base branch, and `-d` walks that ancestry and refuses. Check `allow_squash_merge` from `SKILL.md`'s "Know the repo's merge settings" — where squash is the repo's merge method, go straight to `git branch -D`. The operator's "merged" confirmation (or the watch's `CLOSED state=MERGED`) is what authorises the force delete; git's ancestry check can't.
4. Delete the remote branch **only if the repo doesn't do it for you**: `delete_branch_on_merge` from the settings read says which. When it's on, GitHub already deleted it and step 2's `--prune` cleared your local view — nothing to do. When it's off, `git push origin --delete <branch-name>`.

### Then close the loop, in three sections

Cleanup done, report the cycle to the operator under exactly these three headings, in this order. **Print all three every time; an empty one says so in a few words** — an omitted section reads as "nothing there" and "never considered" alike.

**Actionable is the narrow section, and doubt resolves toward Observations** — the one the operator is invited to skim. An item earns Actionable only by naming a concrete next step and where. One you already judged as not worth raising during the cycle does not earn it here: passing it on hands over the work without the judgement that would let the operator size it. A clean cycle routinely leaves the section empty.

- **Summary** — what happened. The PR by full URL, what shipped as-built, and how the cycle went (rounds, verdicts, anything the review changed about the work). Self-contained: the operator may have been away since the handoff.
- **Observations** — informational, and nothing for them to do. Something surprising in the code you touched, an assumption the change now rests on, a check that passed for a reason worth knowing.
- **Actionable** — findings deferred with "Merge as-is", a follow-up the reviewer raised that you didn't take, setup or config the merged change now needs, an out-of-scope defect you left alone. One line each, naming the concrete next step and where. Out of scope is what qualifies a deferral, not merely having decided against it.

Don't act on that list — filing and fixing are the operator's call, and `issue-workflow` covers the filing once they make it.
