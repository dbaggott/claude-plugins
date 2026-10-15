# Reviewer: issue mode for a tracking issue

Part of the `reviewer` skill. Read this when `references/issue-mode.md`'s
sub-issue snapshot shows children. It reuses that file's discovery,
`references/issue-mode-wait.md`'s wait, and `SKILL.md`'s per-PR review; the
`env -u GH_TOKEN` rule `issue-mode.md` opens with covers every `gh issue` command
here too.

## A tracking issue: whole-project acceptance

A tracking issue's body is a project's design, and its sub-issues carry the work
(`issue-workflow`'s `references/tracking-issue.md`). Each child is reviewed in
its own issue mode. Here you judge whether **the whole was built**, against the
parent's end-to-end acceptance criteria (`A#`), which no child owns and no
per-child review can see. You grade them in one place: the review of the
closeout PR, the one PR that closes the parent (`orchestrate`'s
`references/closeout.md`).

1. **List the children** from `issue-mode.md`'s `fetch-issue-set.sh` snapshot: each
   one's `url` and `state`. Re-run it on every return of the watch below,
   `IDLE` included, rather than reusing the last one. A sub-issue added or
   reopened produces no watch event of its own, so the snapshot is the only
   place it shows up.
2. **Hold until every child is closed.** While any is open, wait on the parent
   and the open children in one call, so a comment or body edit on the parent
   also reaches you. Its `--since` follows the first-arm rule in `watch-issue.sh`'s header: the
   `now=` of step 1's first snapshot.

   ```bash
   "<skill-dir>/../../scripts/watch-issue.sh" <owner>/<repo> <parent> <open child…> \
     --role=reviewer --since=<step 1's snapshot now=> --slug=<slug> \
     [--exclude=<url,url,...>]
   ```

   `<slug>` comes from the reviewer config, as in `issue-mode-wait.md`'s wait. Dispatch
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
   parent. Take the union, reading the per-source fields as `issue-mode.md` describes.
   Check each URL with `gh pr view <url> --json state,closingIssuesReferences`.
   The union is the `MERGED` ones. An open PR on a closed child is not part of
   it, so name that PR in the review.
4. **Find the closeout PR**: the open PR whose `closingIssuesReferences`
   include the parent. It is the only PR you review in this mode. Until one is
   out of draft, wait with step 2's call on the parent alone, re-running
   `pr-sources.sh` on the parent at each return and passing the URL of every
   other PR it finds in `--exclude`, and hold a draft back as `issue-mode.md`
   says.
5. **Grade every `A#` against that union and the closeout PR**, judged on the
   merged result, not on each PR alone. A criterion's `Contributes:` line says
   which children's PRs to read first, but it does not limit what you read. A
   requirement marked `*(end-to-end: A<n>)*` is graded through its `A<n>`. A
   criterion that needs a run is graded by `issue-mode.md`'s rule for a
   criterion met by a run;
   here the record is a section of the closeout PR's description, or a comment
   or PR section linked from the parent or a child. Check the as-built
   doc against the parent body by `closeout.md`'s step 3, and the friction-log
   table by its step 5, as you would any diff against its spec.
6. **Review the closeout PR per `SKILL.md`**: mint a token, review, post, and
   watch. The review body opens with
   `**Project review, round <n>: ACCEPTED**` when you approve and
   `**Project review, round <n>: CHANGES REQUESTED**` when you request changes,
   then gives the merged-PR union by URL and **one line per `A#`, every one
   named**: met, with its evidence (a PR, a file at the merged commit, a
   recorded run), or a finding with the ID `<parent>-B<n>`, or `<parent>-O<n>`
   for an observation. Every round carries every `A#` line, re-graded rather
   than carried over: this overrides `SKILL.md`'s rule that a re-verdict body
   states only what changed, since these lines are what the operator merges
   on.

   Then post a new bot comment on the parent linking that review, one per
   round, so each verdict is reachable from the issue it closes. Write the
   body to a file first, the review's first line and then the review's URL, and
   mint the token in the same call that posts:

   ```bash
   GH_TOKEN="$("<skill-dir>/mint-token.sh" <owner>)" || exit 1
   export GH_TOKEN
   gh api repos/<repo>/issues/<parent>/comments -F body=@<path> --jq '"\(.user.login) \(.id)"'
   ```

   The printed login must be the bot's. If it is not, the token never arrived and the link
   is under the operator's name: delete it with
   `gh api -X DELETE repos/<repo>/issues/comments/<id>`, then fix the mint and
   post again.
7. **Keep watching the parent while you watch the PR**, with step 2's call on
   the parent alone and the closeout PR's URL in its `--exclude`, since the
   PR's own watch covers it, so a child added or reopened reaches you even when
   the PR does not move. On each of its returns, and before each new round, go back
   to step 1. A child open again is unbuilt work: request changes naming it,
   whatever the PR's diff. Report at each verdict, and keep watching after
   it: both watches run in the background, so a turn you end with them armed
   is woken when one returns. The assignment ends when the parent closes.
