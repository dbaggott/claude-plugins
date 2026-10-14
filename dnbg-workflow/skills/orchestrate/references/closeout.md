# Orchestrate: closing out a tracking issue

Part of the `orchestrate` skill. Read this when the operator says "close out
<tracking issue URL>". Run it in the main session, since step 2 needs the
operator's approval.

Closeout takes a finished project, writes its as-built design into the repo,
disposes of its friction log, and closes the tracking issue. The parent's shape
and IDs are in `issue-workflow`'s `references/tracking-issue.md`. Nothing here
merges. The operator merges the doc PR.

## 1. Check the project is accepted

```bash
"<skill-dir>/../../scripts/fetch-issue-set.sh" <owner>/<repo> <n>
gh issue view <n> --repo <owner>/<repo> --json comments --jq '
  [.comments[] | select((.author.login | rtrimstr("[bot]")) == "<slug>"
                        and (.body | startswith("**Project review, round")))]
  | last | {url, verdict: (.body | split("\n")[0]),
           graded: (.body | capture("Graded against body_edited: (?<v>\\S+)").v)}'
```

`<skill-dir>` is the **Base directory** announced when this skill loads, or,
with no skill loaded, the directory holding this file's `references/`. `<slug>`
is the reviewer bot's login, from `jq -r .slug` on the reviewer config, at the
path `reviewer`'s `references/issue-mode.md` reads it from. The verdict is the
one `reviewer` posts in that file's "A tracking issue" mode.

A `result=ERROR` from the snapshot means the set was not read, so stop and say
so. Otherwise, proceed only if all three hold:

- every child's `state` is `CLOSED`;
- the latest verdict reads `ACCEPTED`;
- its `graded` value equals the snapshot's `body_edited`, where `none` matches
  `null`. If not, the review graded a body that has changed since, so a new
  round is owed.

If any check fails, stop and tell the operator which one, with the verdict URL if
there is one (without `AskUserQuestion`:
`<skill-dir>/../issue-workflow/references/delegated.md`, posted on the parent). Closeout never runs ahead of the verdict, and never judges the
criteria itself.

## 2. Dispose of the friction log

Every friction-log entry gets exactly one disposition: a follow-up issue, or
`Dropped, because <reason>`. Draft them all first, as a table, then show the
operator the table and the exact text of every follow-up before filing any. An entry about a
`dnbg-*` plugin's own tooling is filed upstream under the always-on "When shipped
tooling doesn't fit, tell the user" rule, and that rule needs the operator's
approval of the exact text. File the approved follow-ups per `issue-workflow`'s
`references/creating.md`. Without `AskUserQuestion`, the table and the follow-up
texts are the question in `<skill-dir>/../issue-workflow/references/delegated.md`,
posted on the parent; file nothing until it is answered.

Step 4 writes the table into the parent body, in place of the friction log's
bullets. Edit the body there, not now: a body edit after the verdict makes the
check in step 1 fail, and step 1 is what a resumed closeout runs first.

```markdown
| Entry | Disposition |
| --- | --- |
| 2026-10-13: the issue-create hook matches `--help` | <follow-up issue URL> |
| 2026-10-14: author side of a set review is manual | Dropped, because the multi-issue orchestrator now does it |
```

## 3. Write the as-built design, through one PR

`<doc path>` is `docs/design/<name>.md`, where `<name>` is the parent's title
as a lowercase-dashed slug. If the repo already keeps designs somewhere else
under `docs/`, use that location instead. Open the PR per `git-workflow`. Its body
links the parent by URL, **without a closing keyword**: the parent closes in
step 4 with a comment that cites the merged doc, and a keyword would close it at
merge without that comment.

The doc is the parent body as built, not as planned:

- **Open with one line** linking the tracking issue and the `ACCEPTED` verdict.
- **Keep** Problem, Goals, Non-goals, Constraints, Requirements, Decisions, Open
  questions, and End-to-end acceptance criteria, with **every ID unchanged**,
  including retired entries and their markings. Children, PRs and commits cite
  these IDs, and once the issue closes the doc is the only place they still
  resolve.
- **Fold the decision log into the entries it changed.** Each entry reads in
  its final form. If a row's reason is not already in the entry's `Because:`,
  add it there. The log itself does not carry over.
- **Settle each open question.** A decided one points at its `D#`. One still
  carrying its default records the default as what was built.
- **Give each `A#` its evidence**, taken from the verdict's line for it.
- **Replace the candidate decomposition with a "Where it was built" table**: each
  child's title, its `Covers`, and its merged PR URLs.
- **Drop execution state**: the decision log's states, `Depends on`, claims,
  the friction log, and Required reading.

## 4. Close the parent

Once the operator has merged the doc PR, read the merge commit with
`gh pr view <pr> --repo <owner>/<repo> --json mergeCommit --jq .mergeCommit.oid`.
Replace the friction log's bullets in the parent body with step 2's table, then
close the parent with a comment that cites the doc at that commit and the
verdict:

```bash
gh issue close <n> --repo <owner>/<repo> --reason completed --comment "Closed out.
As-built design: https://github.com/<owner>/<repo>/blob/<merge-sha>/<doc path> (<doc PR URL>).
Project review: <verdict comment URL>."
```

Then run `git-workflow`'s post-merge cleanup for the doc PR.
