# Reviewer: issue mode, the discovery loop and the wait

Part of the `reviewer` skill. Read this straight after `references/issue-mode.md`'s
first discovery pass, on every issue-scoped assignment. The `env -u GH_TOKEN`
rule that file opens with covers every `gh issue` command here too.
⚠️ **Discovery is continuous, not one-shot — the set is never frozen.** `issue-mode.md`'s
whole-set rule guards the *spatial* miss (reviewing one PR of a pair). The
*temporal* miss is the likelier one and needs its own guard: siblings are paired
by branch name rather than by when they open (see `git-workflow`, "Multi-repo
changes"), so an infra PR and its app sibling routinely go up hours or days
apart. Discover once and the failure is
worse than missing a PR: the first one merges, you clean up and report the review
complete, and the PR that joins the issue the next day is never looked at. That
is reporting success over half a change.

So the assignment is a loop, not a pass:

1. **Discover** — re-run `pr-sources.sh` as `issue-mode.md` does.
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
conversation. Its `--since` follows the first-arm rule in `watch-issue.sh`'s
header: the `now=` of `issue-mode.md`'s `fetch-issue-set.sh` snapshot, taken before the
discovery pass, so a PR opened while you looked still wakes it.

```bash
"<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <n> [n...] \
  --role=reviewer --since=<the snapshot's now=> \
  --slug="$(jq -r .slug "${DNBG_REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/reviewer}/config.json")" \
  [--exclude=<url,url,...>]
```

It wakes on a comment, a body edit, a linked PR appearing, or the issue closing,
and names which of those fired on which issue. Several issues cost one call per
tick, so watching the whole set you were handed is no more expensive than
watching one.


The issue wait never stands in for a PR watch: every open PR you reviewed or
held back as a draft keeps its own `watch-pr.sh` beside it, an approved one
included, since a push after approval needs a re-verdict (`references/watch.md`,
"End state").

**At most one issue wait at a time, re-armed only on its own return, from its `── re-arm ──` line.** A PR
watcher returning is a trigger to re-discover, not to arm a second wait — two
waits on one issue each paginate the whole timeline every tick and both report
the same `CLOSED`.

`watch-issue.sh`, the issue-side sibling of the PR watch — same backoff curve,
same failure counting, same re-arm contract. It returns `ACTIVITY` when a comment,
a body edit or a linked PR lands (`kinds=` says which), `CLOSED` if the issue
closes, `IDLE` on timeout, and `ERROR reason=issue-query` when its query keeps
failing.

**The wait polls `issue-mode.md`'s sources 1 and 2, not source 1 alone.** It has to: source
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
- **`CLOSED`** — run step 1's discovery once more; an open PR it finds keeps
  the assignment going, and a printed re-arm line still covers the other
  issues. A merge of a PR you reviewed is reported once, at its own watch's
  `CLOSED`, which can arrive after this one, so check each PR you reviewed with
  `gh pr view <url> --json state,closingIssuesReferences` and report the close
  here only when none of them caused it: the work was dropped or resolved
  without a PR.
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
