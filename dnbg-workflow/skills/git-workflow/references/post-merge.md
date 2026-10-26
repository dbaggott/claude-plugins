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
4. Delete the remote branch **only if the repo doesn't do it for you**: `delete_branch_on_merge` from the settings read says which. When it's on, GitHub already deleted it and step 2's `--prune` cleared your local view — nothing to do. When it's off, delete it as the author, who pushed it: `"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch-name>`. A `git push` from the main checkout would go up under your own credential.

### Then report what changed since the handoff

Cleanup done, report to the operator under the same three headings the handoff carried (`references/merge.md`'s "The report that goes with the command"), in the same order. The handoff report is the baseline: under each heading put only what arrived after it — a late reviewer comment, a conflict, a check that went red and was fixed — and Summary opens with the PR's full URL and the cleanup. A new Actionable item gets its follow-up entry as `references/merge.md` says. Where a heading has nothing new, say "nothing new since the handoff" rather than repeating it; a second copy of the report is the one that drifts from the first.

Where you have no handoff report to measure against — this session only opened the PR, or the handoff is no longer in your context — give the full report as `references/merge.md` defines it.
