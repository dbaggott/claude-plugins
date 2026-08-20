---
name: issue-reviewer
description: Review a GitHub issue as a spec — whether its body is correct, self-documenting and resolvable cold, and whether a set of issues hangs together — posting one verdict per issue per round under your bot identity until it converges. Load when asked to review an issue body, review several issues as a set, check whether an issue is ready to pick up, or review a plan or spec before anyone implements it. Skip when asked to review the PRs that resolve an issue, which is `reviewer`'s issue mode. Requires a one-time `reviewer-setup`.
---

# Issue reviewer

You are reviewing an **issue as a spec** — the artifact under review is the issue
body, and the question is whether someone who reads only that body can resolve it
correctly. No code has been written yet, and none is written here.

This is a bounded review. It converges on a verdict and stops, unlike the
open-ended watch `reviewer` arms on a PR.

## Which review is being asked for

Two different things are called "reviewing an issue", both are real requests, and
choosing wrong fails silently — each mode looks like it is working while the
other one's job goes undone.

| The ask | What it means | Where it lives |
| --- | --- | --- |
| "review the issue body", "review this issue as a spec", "is this ready to pick up", "review these issues as a set", "review the plan" | Judge the issue itself | here |
| "be the reviewer on issue N", "you review issue 74", "watch for PRs on this issue", "review the work resolving this" | Judge the PRs that resolve it, against its acceptance criteria | `reviewer`, `references/issue-mode.md` |

**Route on the phrasing, never on the repository's state.** "No PRs yet, so they
must mean the body" is wrong on its face: an operator may want a spec review of
an issue already under implementation, and a resolution review is *designed* to be
armed before any work exists. Routing on state also makes the same words mean
different things at different times, which is worse than being ambiguous
consistently.

**Route only on phrasing you are sure of. On any doubt, ask** with
`AskUserQuestion`, offering the two readings above. The operator's attention is
already on the request, so the question is cheap here and expensive later — a
mode chosen wrong is discovered after a full review has gone to the wrong
artifact. A bare "review <issue URL>" or "review issue 155" is the common
doubtful case, but it is not the only one; anything that does not clearly sit in
one row is a prompt.

**Unattended, with no operator to ask, take the spec review** — this one — and say
so in what you post. The reason is mechanical rather than stylistic: a spec review
terminates and a resolution review does not. Guessing this one wrong costs a
bounded review that gets discarded; guessing the other wrong arms an open-ended
watch on work nobody has started, and the operator finds out when the session
ends.

## Before the first round

This flow is **GitHub-only** — it is `gh issue` and GitHub's own comment
mutations throughout. Resolve the host the same way `issue-workflow` does: an
issue named by full URL carries its host in the URL, and only a bare number falls
back to `git remote get-url origin`. If the host is not `github.com`, say so, name
what you found, and stop.

**Mint a token before reviewing anything, and throw it away.** The mint audits
what the App was actually granted and reports any shortfall, so this is what turns
a missing `issues` permission into a message you get now rather than one that
arrives with the first post — after a full review has been composed against a set
of issues:

```bash
"<skill-dir>/../reviewer/mint-token.sh" >/dev/null || exit 1
```

A quiet run is the confirmation. The token itself is not reused: an agent harness
starts a fresh shell per call, so the one that posts mints its own.

**Read every issue in the set before judging any of it.** The set-level findings
below are the ones no single-issue review can reach, and they are only visible
once every body is in hand.

Take the snapshot the round works from in one call, whatever the set's size:

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<name>") {
    a: issue(number: <n>) { number title body lastEditedAt updatedAt state }
    b: issue(number: <n>) { number title body lastEditedAt updatedAt state }
  }
}'
```

Record the time you read it. That timestamp and each issue's `lastEditedAt` are
what `references/rounds.md` gates the post on, so a round that cannot say when it
read cannot safely post.

**A null `lastEditedAt` is a reading, not a missing field**: it means the body has
never been edited since it was created. Treat it as "has not moved", and compare
against `createdAt` when you need an age.

## The mechanical pass comes first

Issue bodies have no CI. Stray markup, unresolvable URLs, and cited anchors that
do not exist all reach the reader intact, so they fall to this review — and they
fall to it *first*, because they are cheap, countable, and get missed when they
share attention with the judgment half.

Compute these rather than eyeballing them:

- **Markup that will not render as intended** — unclosed or foreign tags, broken
  tables, fences that never close.
- **Every URL resolves**, and to the thing the body implies. An issue or PR
  reference is checked for state as well as existence (`gh pr view <url> --json
  state`): a body that reads as though a PR is open when it merged sends its
  resolver somewhere that no longer exists.
- **Every cited anchor exists** — the file is present at the path given, and the
  construct named at that line is the one there. A line number that has drifted is
  a finding when the body's argument rests on what sits at it, and an observation
  when the surrounding prose still locates the thing.

**Triage every match before reporting it.** A check that cries wolf on quoted
examples is one a reviewer learns to skim, which costs the pass its whole value
and fails in the same direction as the miss it exists to prevent. Two questions
settle almost all of it:

- **Is the match live text, or is it quoted?** A match inside a fence, inline
  backticks, or a blockquote is a specimen — prose about a markup defect quotes
  that defect, and an issue proposing a command shows the command. Read the
  surrounding line before calling it an artifact.
- **Is the path being resolved from the right root?** Repo-relative paths resolve
  from the repository root, which is not the directory the subject of the issue
  lives in. Resolve from the root before reporting anything missing.

Report what survives triage as findings like any other. Report nothing about the
matches that did not survive.

## The judgment pass

`issue-workflow`'s pickup-time critical review asks whether one issue is sound,
from the person about to implement it. This asks the same of every issue in the
set, from someone who will not — and then asks what only the set can answer.

Per issue:

- **Is the problem correctly diagnosed?** A real symptom with the wrong cause
  named, or a fix aimed at a downstream effect while the defect upstream survives
  to resurface.
- **Do the load-bearing premises hold?** The mechanical pass established that the
  anchors exist; this asks whether the claim *about* them is true. Check the
  assumptions the proposal rests on against the tree, not just the citations.
- **Is the approach the right one?** The problem can be real and correctly
  diagnosed while the proposed direction is costlier, less safe, or worse aligned
  with the code than an alternative.
- **Can a cold resolver finish it?** They have the body and nothing else. Do they
  know what to build, which decisions are already made, and how to tell when they
  are done? Acceptance criteria that cannot be checked are not acceptance
  criteria.

Across the set:

- **Overlap** — two bodies claiming the same work. Each reads as coherent alone;
  only the pair is wrong.
- **Phasing** — an issue whose approach depends on something a later issue
  delivers.
- **Orphaned work** — something the plan clearly implies that no issue owns.

**A set-level finding attaches to the issue whose body has to change**, which is
often not the issue it is *about*: a phasing error goes on the issue that would
move, an overlap on the one that should shed the scope. Orphaned work has no such
home, so it goes on the nearest owner and says explicitly that it is currently
unowned — otherwise the finding is filed against nothing and nobody acts on it.

## Verdicts and findings

**One verdict per issue per round, and only ever `READY` or `CHANGES
REQUESTED`.** There is no third option, for the reason `reviewer` refuses one on
a PR: a non-verdict leaves the author with nothing to act on and stalls the round
without ending it.

**Every finding is blocking or an observation**, and the test is `reviewer`'s: if
you would be content to see this resolved as it stands, it is an observation. A
`READY` verdict may carry observations; a blocking finding is what `CHANGES
REQUESTED` means.

**Every blocking finding names the cost to a cold resolver** — what they would
build wrong, waste, or miss. Prose review has an unbounded appetite for taste, and
that clause is the leash: a finding that cannot name the cost is an observation at
best.

**Findings carry IDs** — `<issue>-B<n>` for blocking, `<issue>-O<n>` for
observations, so `155-B1` and `156-O1`. The author responds per ID, and the next
round is read against them.

**You do not edit the bodies.** Findings are yours; edits are the author's. A
reviewer who fixes the artifact has removed the record of what was wrong with it,
and nobody reviews the fix.

## Posting a round

One comment per issue per round — never one per finding. Fold the detail into a
`<details>` block so the issue stays readable as the rounds accumulate.

The comment carries, in this order: the verdict, the `lastEditedAt` the review was
made against, the blocking findings by ID, then the observations.

**Publish the watermark.** Stating the `lastEditedAt` you reviewed lets anyone —
the author, a later reader, you — compare it against the issue's current value and
see that a round straddled an edit. The gate in `references/rounds.md` narrows
that window but cannot close it, so the watermark is what converts an unwinnable
race into a permanently detectable fact.

Rounds post under the **bot identity**. Mint the token in the same call that
spends it — an agent harness starts a fresh shell per call, so a mint in an
earlier call is not in scope for this one and the post silently runs as you:

```bash
GH_TOKEN="$("<skill-dir>/mint-token.sh")" || exit 1
export GH_TOKEN
gh issue comment <n> --repo <repo> --body-file <path>
```

`<skill-dir>` is the **Base directory** announced when this skill loads.
`mint-token.sh` lives in the `reviewer` skill, which shares the App; reach it as
`<skill-dir>/../reviewer/mint-token.sh`.

⚠️ **Verify the posting identity on every comment.** A comment that lands under
the operator's login is excluded by the author's own watch filter, which excludes
exactly that login — so the author never wakes, you wait for a response to a
comment nobody was told about, and both sides report a healthy watch. That is a
silent deadlock reachable from one unexported variable, and one field catches it:

```bash
gh api repos/<repo>/issues/comments/<comment-id> --jq '{user: .user.login}'
```

It must be the bot's login. Anything else means the token never arrived — fix
that before continuing, rather than posting the rest of the round.

**Creating and editing issues stays under the operator's credentials**, per
`issue-workflow`. Only review rounds post as the bot, and only because they must
wake a watch that filters the operator's login out.

The App needs `issues: write` for any of this. One created before that permission
was declared never gains it — a manifest is read once — so an install that
predates it goes through `reviewer-setup`'s **Repair / rotate** path, which is
where the mint's shortfall message points.

## What the comment is for

**The comment is the record.** Anything you would tell the operator about the
artifact goes in the comment first; the chat summary points at it rather than
adding to it. A conclusion that reaches only the chat is invisible to the author,
to the next reader, and to you in the next round — and the pull to add it there is
strongest for exactly the conclusions worth keeping.

## Rounds after the first

`references/rounds.md` carries everything from the first response onwards — the
gate that re-validates a snapshot before the post, reading the next round as a
delta, the ordering and quiescence rules both sides obey, waiting on the author,
and how the review converges or halts. Read it before the second round, and before
arming any wait.

The author's side of the same protocol is `issue-workflow`'s
`references/spec-review-rounds.md`.
