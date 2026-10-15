# Git workflow: composing the merge command

Part of the `git-workflow` skill. Read this once a review is clean and you are
composing the merge handoff; `references/review-received.md` routes here.
`references/merge-wait.md` carries the watch until the merge lands, and
`references/post-merge.md` the cleanup after it.

## Composing the merge command

Whenever you hand the operator a merge command, emit exactly one form — the right one for the observed state. (That's the immediately-runnable one in every case but the no-auto-merge-with-pending-checks branch below, where no immediately-runnable form exists and the handoff says so.) A clean review does not mean the PR is mergeable *right now*: a review on a fresh push usually lands while checks are still re-running, and where any of those are *required*, a plain `gh pr merge` is refused until they pass. Don't present `--auto` as an optional garnish ("add `--auto` if you want it to wait...") — you have the data to decide, so deciding is your job, not the operator's.

Two inputs. The **repo settings** — `allow_auto_merge` and which merge methods are enabled — come from `SKILL.md`'s "Know the repo's merge settings". The **live merge state** has to be read now:

```bash
"<skill-dir>/../../scripts/fetch-pr-state.sh" <owner>/<repo> <num> | head -1
```

That object carries `.merge.status`, `.merge.cause`, and `.checks[]` already normalised to `success` / `failure` / `pending` / `neutral`. Read the checks off it rather than off a raw rollup: GitHub returns two different shapes there — a CheckRun with `.name`/`.status`/`.conclusion`, a StatusContext with `.context`/`.state` — and an unfinished check carries no conclusion at all, so a hand-rolled parse that misses the fallback reads a running check as a failed one.

```bash
# the non-passing checks, both shapes, in one vocabulary
… | jq -r '.checks[] | select(.state == "failure" or .state == "pending") | "\(.name) \(.state)"'
```

Pick the merge-method flag from what the repo actually allows (`--squash`, `--merge`, or `--rebase`); if several are enabled, prefer the repo's own convention, and `--squash` when there's no signal. Then pick the form by state:

- **`status=clean`** — plain form: `gh pr merge <num> --repo <repo> <method> --delete-branch`.
- **`status=unstable`** — mergeable, with at least one check not passing. Hand over the same plain form, and hand it over now: GitHub will merge this PR on request, and a check the repo actually gates on never lands here (a red *required* check reads as `blocked`), so there is nothing to withhold the command over. What changes is that it doesn't go out *unqualified* — `unstable` says nothing about whether the failing check was *required*, so on a repo that requires none, a completely red build arrives here looking mergeable. Name the non-passing checks alongside the command, using the jq above. Split on what it reports — and where both apply, one check still `pending` and another already `failure`, the failure decides the framing:
  - **Still running** (`pending`) — name the checks in flight and say plainly that nothing is holding the merge for them. Whether to let them land first is the operator's call, and it is not a reason to make them wait on the command. Don't reach for `--auto` here: GitHub offers auto-merge only on a PR that *can't* merge yet, and it waits on required gates, none of which are outstanding in this state.
  - **Finished non-passing** (`failure`) — name each check and its state, and don't call the PR ready to merge. The command is still theirs to run; just be plain that nothing on the repo will stop it.
- **`status=blocked`, `cause=checks_running` or `checks_expected`, `allow_auto_merge=true`** — auto form: `gh pr merge <num> --repo <repo> <method> --delete-branch --auto`. The plain form would be refused right now; `--auto` queues the merge to fire when checks pass. (`checks_expected` is the same wait one step earlier: a required check that has not reported yet, so there is nothing in the rollup to count.)
- **same two causes, `allow_auto_merge=false`** — both forms are refused right now (`--auto` needs the repo setting). Give the plain form, but say explicitly that required checks are still outstanding and the command will work once they're green — the browser merge button enables at the same moment.
- **`status=blocked`, any other cause** — the PR is not actually mergeable. `checks_failing` names a red required check, `review_required` an approval that has not been given, `terminal` something only a human clears. Don't send a ready-to-merge handoff at all; surface the cause and ask.
- **`status=behind`** — the base moved on and the branch needs an "Update branch" click before it can merge. Say so; under a merge queue it often clears unaided.
- **`status=indeterminate`** — GitHub is recomputing mergeability and has no answer yet. This is routine right after a push, which is exactly when this stage reads. Wait a few seconds and read again rather than composing a handoff on it.
- **`status=unrecognised`** — GitHub returned a merge status this mapping has never seen, so the schema moved. Don't guess what it means: say what came back, and re-run `tests/fixtures/capture-enums.sh` to see what changed.

Drop `--delete-branch` when `delete_branch_on_merge` is already on for the repo — it's redundant there, though harmless.

For a multi-repo PR set (see `SKILL.md`'s "Multi-repo changes"), run both reads **per repo** — siblings can need different forms, because both the check state and the repo settings differ across repos.

**Formatting:** put each merge command on its own line in a fenced code block, never inline in a sentence or bullet — inline commands can't be cleanly triple-click-selected or copy-pasted. For a multi-PR handoff, one block with one command per line:

```
gh pr merge 247 --repo <owner>/infrastructure --squash --delete-branch --auto
gh pr merge 48 --repo <owner>/examples --squash --delete-branch
```

(Don't column-align the commands with padding spaces — extra whitespace inside a command is harmless but looks like it might not be.)


