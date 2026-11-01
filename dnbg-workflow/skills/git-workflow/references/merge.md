# Git workflow: composing the merge command

Part of the `git-workflow` skill. Read this the first time in the session a
review is clean and you are composing the merge handoff, and compose a later
handoff, such as one after a re-verdict, from that copy. Read it again when the
watch result that brought you here is `ERROR`, when a watch returned no
`result=` line, or when the context has been compacted since you read it.
`references/review-received.md` routes here.
`references/merge-wait.md` carries the watch until the merge lands, and
`references/post-merge.md` the cleanup after it.

## Composing the merge command

Whenever you hand the operator a merge command, emit exactly one form — the right one for the observed state. (That's the immediately-runnable one in every case but the no-auto-merge-with-pending-checks branch below, where no immediately-runnable form exists and the handoff says so.) A clean review does not mean the PR is mergeable *right now*: a review on a fresh push usually lands while checks are still re-running, and where any of those are *required*, a plain `gh pr merge` is refused until they pass. Don't present `--auto` as an optional garnish ("add `--auto` if you want it to wait...") — you have the data to decide, so deciding is your job, not the operator's.

Two inputs. The **repo settings** — `allow_auto_merge` and which merge methods are enabled — come from `SKILL.md`'s "Know the repo's merge settings". The **live merge state** has to be read now:

```bash
"<skill-dir>/../../scripts/fetch-pr-state.sh" <owner>/<repo> <num> | head -1
```

That object carries `.merge.status`, `.merge.cause`, and `.checks[]` already normalised to `success` / `failure` / `cancelled` / `pending` / `neutral`. Read the checks off it rather than off a raw rollup: GitHub returns two different shapes there — a CheckRun with `.name`/`.status`/`.conclusion`, a StatusContext with `.context`/`.state` — and an unfinished check carries no conclusion at all, so a hand-rolled parse that misses the fallback reads a running check as a failed one.

```bash
# the non-passing checks, both shapes, in one vocabulary
… | jq -r '.checks[] | select(.state == "failure" or .state == "cancelled" or .state == "pending") | "\(.name) \(.state)"'
```

Pick the merge-method flag from what the repo actually allows (`--squash`, `--merge`, or `--rebase`); if several are enabled, prefer the repo's own convention, and `--squash` when there's no signal. Then pick the form by state:

- **`status=clean`** — plain form: `gh pr merge <num> --repo <repo> <method> --delete-branch`.
- **`status=unstable`** — mergeable, with at least one check not passing. Hand over the same plain form, and hand it over now: GitHub will merge this PR on request, and a check the repo actually gates on never lands here (a red *required* check reads as `blocked`), so there is nothing to withhold the command over. What changes is that it doesn't go out *unqualified* — `unstable` says nothing about whether the failing check was *required*, so on a repo that requires none, a completely red build arrives here looking mergeable. Name the non-passing checks alongside the command, using the jq above. Split on what it reports — and where both apply, one check still `pending` and another already finished non-passing, the finished one decides the framing:
  - **Still running** (`pending`) — name the checks in flight and say plainly that nothing is holding the merge for them. Whether to let them land first is the operator's call, and it is not a reason to make them wait on the command. Don't reach for `--auto` here: GitHub offers auto-merge only on a PR that *can't* merge yet, and it waits on required gates, none of which are outstanding in this state.
  - **Finished non-passing** (`failure` or `cancelled`) — name each check and its state, and don't call the PR ready to merge. The command is still theirs to run; just be plain that nothing on the repo will stop it.
- **`status=blocked`, `cause=checks_running` or `checks_expected`, `allow_auto_merge=true`** — auto form: `gh pr merge <num> --repo <repo> <method> --delete-branch --auto`. The plain form would be refused right now; `--auto` queues the merge to fire when checks pass. (`checks_expected` is the same wait one step earlier: a required check that has not reported yet, so there is nothing in the rollup to count.)
- **same two causes, `allow_auto_merge=false`** — both forms are refused right now (`--auto` needs the repo setting). Give the plain form, but say explicitly that required checks are still outstanding and the command will work once they're green — the browser merge button enables at the same moment.
- **`status=blocked`, any other cause** — the PR is not actually mergeable. `checks_failing` names a red required check, `review_required` an approval that has not been given, `terminal` something only a human clears. Don't send a ready-to-merge handoff at all; surface the cause and ask.
- **`status=behind`** — the base moved on and the branch needs an "Update branch" click before it can merge. Say so; under a merge queue it often clears unaided.
- **`status=indeterminate`** — GitHub is recomputing mergeability and has no answer yet. This is routine right after a push, which is exactly when this stage reads. Wait a few seconds and read again rather than composing a handoff on it.
- **`status=unrecognised`** — GitHub returned a merge status this mapping has never seen, so the schema moved. Don't guess what it means: say what came back, and re-run `tests/fixtures/capture-enums.sh` to see what changed.

Drop `--delete-branch` when `delete_branch_on_merge` is already on for the repo — it's redundant there, though harmless.

### A PR in a stack

Before composing any merge command, read the PR's stack, one `GET`:

```bash
"<skill-dir>/../../scripts/stack-prs.sh" <owner>/<repo> <num>
```

At `stack=none`, nothing above changes. At `result=ERROR reason=stack-read`, carry no command and say the stack could not be read, since it decides the command's form. At `stack=<n>`, GitHub refuses `gh pr merge`, whatever the PR's base is now, and the command block is its asynchronous merge, with the repo's merge method in place of `squash` where it differs and `<head>` the full SHA `pr-verdict.sh` read, followed by a read of its result until it leaves `pending`. It lands `<num>` together with every PR in `below=`:

```
r=$(gh api --method PUT repos/<owner>/<repo>/pulls/<num>/merge-async -f merge_method=squash -f sha=<head>) && u=$(jq -r '.details.uuid // empty' <<<"$r") || u=
for i in $(seq 40); do [ -n "$u" ] || break; s=$(gh api repos/<owner>/<repo>/pulls/<num>/merge-async/$u --jq '.status + " " + (.details.sha // .details.message // "")'); case $s in pending*) sleep 3 ;; *) break ;; esac; done; echo "${s:-$r}"
```

`sha=<head>` makes a push to `<num>` in between cancel the merge rather than land a head nobody approved; the PRs in `below=` are pinned only by the reads below. The block ends by printing `merged <sha>`, `failed <message>`, `enqueued` (a merge queue took the stack; your watch reports the landing when it merges), or `pending` after two minutes, when the second line is run again. With no UUID it prints the `PUT`'s own answer: a 200 means the PR was already merged or queued, a 409 that an earlier request is still running and nothing new was asked. Repository rules run only when the merge executes, so a `failed` reaches nothing but that status, and your merge watch, which reports a landing, cannot see it. Say so in the handoff, and that a `failed` comes back to you as a merge that did not happen, which you surface and ask about. Say too that a merge run from a PR in `below=` instead lands only that PR and the ones under it, leaving this PR open for GitHub to rebase, with a fresh handoff after its re-verdict. Read `pr-verdict.sh` and `fetch-pr-state.sh` on each PR in `below=` as on `<num>`: the command goes out only when every one is approved at head under `SKILL.md`'s "Know the repo's merge settings" rule, and the form is picked by the worst merge state among them, since the landing fails on any of them. When one is not approved or not mergeable, name the lowest such PR as what the merge waits on and carry no command. The call takes no `--auto`, so where a form above would add it, name the checks still outstanding and say the command works once they pass. It takes no `--delete-branch` either; `references/post-merge.md` step 4 deletes the remote branch where the repo does not. A failure partway through a stack leaves the PRs below the failed one landed, so their authors see the merge, and the failed one and those above it open.

A stacked PR, one whose base is not the default branch, that records no stack would merge into its base's branch, so its handoff carries no merge command: it says the PR is approved and waits on its base PR, and the command comes in the fresh handoff after the rebase (`references/merge-wait.md`, "A stacked PR whose base moved").

For a multi-repo PR set (see `SKILL.md`'s "Multi-repo changes"), run both reads **per repo** — siblings can need different forms, because both the check state and the repo settings differ across repos.

**Formatting:** put each merge command on its own line in a fenced code block, never inline in a sentence or bullet — inline commands can't be cleanly triple-click-selected or copy-pasted. For a multi-PR handoff, one block with one command per line:

```
gh pr merge 247 --repo <owner>/infrastructure --squash --delete-branch --auto
gh pr merge 48 --repo <owner>/examples --squash --delete-branch
```

(Don't column-align the commands with padding spaces — extra whitespace inside a command is harmless but looks like it might not be.)

## The report that goes with the command

Below the command, report the cycle per
`<skill-dir>/../findings-review/references/report.md`. The operator reads it
before deciding to merge, so an item here can still send the PR back for one
more change, where the same item read after the merge costs a second PR.

- **Summary**: the PR, what it ships as-built, and how the cycle went (rounds,
  verdicts, anything the review changed about the work).
- **Observations**: something surprising in the code you touched, an
  assumption the change now rests on, a check that passed for a reason worth
  knowing, and a finding you declined because the operator told you to, naming
  where they said so.
- **Actionable**: findings deferred with "Merge as-is", a follow-up the reviewer
  raised that you didn't take on your own judgement, setup or config the merged
  change will need, an out-of-scope defect you left alone.

Write each item's findings entry now, at this handoff, per
`<skill-dir>/../findings-review/references/entry.md`, and name its path on the
item's line. The operator-ordered decline gets none. Process friction that did
not stop the task, such as a skill step that did not fit, goes under none of
these headings, Actionable included, and is not offered for filing here: it
waits for your close-out, per `report.md`'s "At a close-out".

This report is the handoff the post-merge report in `references/post-merge.md`
is a delta against.
