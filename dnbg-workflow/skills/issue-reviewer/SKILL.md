---
name: issue-reviewer
description: Review a GitHub issue as a spec — whether its body is correct, self-documenting and resolvable cold, and whether a set of issues hangs together — posting one verdict per issue per round under your bot identity until it converges. Load when asked to review an issue body, review several issues as a set, check whether an issue is ready to pick up, or review a plan or spec before anyone implements it. Skip when asked to review the PRs that resolve an issue, which is `reviewer`'s issue mode. Requires a one-time `reviewer-setup`.
---

# Issue reviewer

You are reviewing an **issue as a spec**: the artifact is the issue body, and the
question is whether someone who reads only that body can resolve it correctly. No
code is written here.

## Which review is being asked for

"Reviewing an issue" names two different things, both real requests, and choosing
wrong fails silently — each mode looks like it is working while the other one's
job goes undone.

| The ask | What it judges | Where it lives |
| --- | --- | --- |
| "review the issue body", "review this issue as a spec", "is this ready to pick up", "review these issues as a set", "review the plan" | the issue itself | here |
| "be the reviewer on issue N", "you review issue 74", "watch for PRs on this issue", "review the work resolving this" | the PRs that resolve it, against its acceptance criteria | `reviewer`, `references/issue-mode.md` |

**Route on the phrasing, not on the repository's state.** "No PRs yet, so they
must mean the body" is wrong: a spec review of an issue already under
implementation is a coherent ask, and a resolution review is designed to be armed
before any work exists.

**On any doubt, ask** with `AskUserQuestion`, offering both readings. A bare
"review <issue URL>" is the common doubtful case, not the only one. The operator's
attention is on the request now, and a mode chosen wrong surfaces only after a
full review has gone to the wrong artifact.

**Unattended, take the spec review** — this one — and say so in what you post. It
terminates and a resolution review does not, so guessing this way costs a bounded
review that gets discarded, and the other way arms an open-ended watch on work
nobody has started.

## Before the first round

This flow is **GitHub-only**. Resolve the host as `issue-workflow` does: an issue
named by full URL carries its host, and only a bare number falls back to
`git remote get-url origin`. If it is not `github.com`, say so, name what you
found, and stop.

**Mint a token before reviewing anything, and discard it.** The mint audits what
the App was actually granted, so a missing `issues` permission surfaces now rather
than with the first post — after a full review has been composed:

```bash
"<skill-dir>/../reviewer/mint-token.sh" >/dev/null || exit 1
```

A quiet run is the confirmation. `<skill-dir>` is the **Base directory** announced
when this skill loads; the script lives in `reviewer`, which shares the App.

**Read every issue in the set before judging any of it** — the set-level findings
below are visible only once every body is in hand.

Snapshot the set in one call, whatever its size:

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<name>") {
    a: issue(number: <n>) { number title body lastEditedAt createdAt updatedAt state }
    b: issue(number: <n>) { number title body lastEditedAt createdAt updatedAt state }
  }
}'
```

Record the time you read it: that, and each issue's `lastEditedAt`, are what
`references/rounds.md` gates the post on.

**A null `lastEditedAt` is a reading, not a missing field** — the body has never
been edited. Treat it as "has not moved", and use `createdAt` when you need an age.

## The mechanical pass comes first

Issue bodies have no CI, so stray markup, unresolvable URLs, and cited anchors
that do not exist all reach the reader intact. They come first because they are
cheap, countable, and get missed when they share attention with the judgment half.

Compute these rather than eyeballing them:

- **Markup that will not render as intended** — unclosed or foreign tags, broken
  tables, fences that never close.
- **Every URL resolves**, and to the thing the body implies. Check a referenced
  issue or PR for state as well as existence (`gh pr view <url> --json state`): a
  body reading as though a PR is open when it merged sends its resolver somewhere
  that no longer exists.
- **Every cited anchor exists** — the file is at the path given, and the construct
  named at that line is the one there. A drifted line number is a finding when the
  body's argument rests on what sits at it, an observation when the surrounding
  prose still locates the thing.

**Triage every match before reporting it.** A check that cries wolf on quoted
examples is one a reviewer learns to skim, which costs the pass its whole value
and fails in the same direction as the miss it exists to prevent. These questions
settle almost all of it:

- **Is the match live text, or quoted?** A match inside a fence, inline backticks,
  or a blockquote is a specimen — prose about a markup defect quotes that defect,
  and an issue proposing a command shows the command.
- **Is the path resolved from the right root?** Repo-relative paths resolve from
  the repository root, not from the directory the issue's subject lives in.

Report what survives triage as findings like any other.

## The judgment pass

`issue-workflow`'s pickup-time critical review asks whether one issue is sound,
from the person about to implement it. This asks that of every issue in the set,
from someone who will not — then asks what only the set can answer.

Per issue:

- **Is the problem correctly diagnosed?** A real symptom with the wrong cause
  named, or a fix aimed at a downstream effect while the defect upstream survives
  to resurface.
- **Do the load-bearing premises hold?** The mechanical pass established that the
  anchors exist; this asks whether the claim *about* them is true. Check the
  assumptions against the tree, not just the citations.
- **Is the approach the right one?** A problem can be real and correctly diagnosed
  while the proposed direction is costlier, less safe, or worse aligned with the
  code than an alternative.
- **Can a cold resolver finish it?** They have the body and nothing else. Do they
  know what to build, which decisions are already made, and how to tell when they
  are done? Acceptance criteria that cannot be checked are not acceptance criteria.

Across the set:

- **Overlap** — two bodies claiming the same work. Each reads as coherent alone;
  only the pair is wrong.
- **Phasing** — an issue whose approach depends on what a later issue delivers.
- **Orphaned work** — something the plan implies that no issue owns.

**A set-level finding attaches to the issue whose body has to change**, which is
often not the issue it is *about*: a phasing error goes on the issue that would
move, an overlap on the one that should shed the scope. Orphaned work has no such
home, so it goes on the nearest owner and says explicitly that it is unowned —
otherwise it is filed against nothing.

## Verdicts and findings

**One verdict per issue per round, and only ever `READY` or `CHANGES
REQUESTED`.** A third option leaves the author nothing to act on, stalling the
round without ending it.

**Every finding is blocking or an observation**: if you would be content to see it
resolved as it stands, it is an observation. A `READY` may carry observations; a
blocking finding is what `CHANGES REQUESTED` means.

**Every blocking finding names the cost to a cold resolver** — what they would
build wrong, waste, or miss. Prose review has an unbounded appetite for taste, and
that clause is the leash: a finding that cannot name the cost is an observation.

**Findings carry IDs** — `<issue>-B<n>` blocking, `<issue>-O<n>` observations, so
`155-B1` and `156-O1`. The author responds per ID, and the next round is read
against them.

**You do not edit the bodies.** A reviewer who fixes the artifact has removed the
record of what was wrong with it, and nobody reviews the fix.

## Posting a round

One comment per issue per round, never one per finding, with the detail folded
into a `<details>` block. It carries, in order: the verdict, the `lastEditedAt`
the review was made against, the blocking findings by ID, then the observations.

**Publishing that `lastEditedAt` is what makes a round that straddled an edit
detectable afterwards** — the gate in `references/rounds.md` narrows that window
but cannot close it.

Rounds post under the **bot identity**. Mint the token in the same call that
spends it: an agent harness starts a fresh shell per call, so a mint in an earlier
call is not in scope for this one and the post silently runs as you.

```bash
GH_TOKEN="$("<skill-dir>/../reviewer/mint-token.sh")" || exit 1
export GH_TOKEN
gh issue comment <n> --repo <repo> --body-file <path>
```

⚠️ **Verify the posting identity on every comment.** A comment landing under the
operator's login is excluded by the author's own watch, which filters exactly that
login — so the author never wakes, you wait for a response to a comment nobody was
told about, and both sides report a healthy watch. One field catches it:

```bash
gh api repos/<repo>/issues/comments/<comment-id> --jq '{user: .user.login}'
```

Anything but the bot's login means the token never arrived. Fix that before
posting the rest of the round.

**Creating and editing issues stays under the operator's credentials**, per
`issue-workflow`; only review rounds post as the bot, and only because they must
wake that watch.

The App needs `issues: write`. One created before that permission was declared
never gains it — a manifest is read once — so an older install goes through
`reviewer-setup`'s **Repair / rotate** path, which is where the mint's shortfall
message points.

**The comment is the record.** Anything you would tell the operator about the
artifact goes in the comment first; the chat summary points at it rather than
adding to it. A conclusion that reaches only the chat is invisible to the author,
to the next reader, and to you next round.

## Rounds after the first

`references/rounds.md` carries everything from the author's first response
onwards — the gate that re-validates a snapshot before the post, reading a round
as a delta, the ordering and quiescence rules both sides obey, waiting, and how
the review converges or halts. Read it before the second round, and before arming
any wait.

The author's side of the same protocol is `issue-workflow`'s
`references/spec-review-rounds.md`.
