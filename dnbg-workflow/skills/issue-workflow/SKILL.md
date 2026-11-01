---
name: issue-workflow
description: "How to create, maintain, and pick up GitHub issues so context survives the handoff to whoever resolves them cold. Load when about to create a GitHub issue (any `gh issue create`), file follow-up work as an issue, update one after partial progress or a referenced PR closing, label one along the type and `area:*` axes, assign or dispatch one to anyone (person or bot), decide whether a discussion is one issue or a tracking issue, decompose an accepted tracking issue into child issues, or pick up an issue named by number or URL (\"resolve #245\", \"do issue 245\", \"work on <issue URL>\") — on pickup load this *before* reading any file or opening a worktree, since claiming the issue comes first. Also load before a PR leaves draft when the implementation departed from the approach the issue described, and when answering a reviewer's findings on an issue body you wrote. The pickup trigger is an issue being named, not the user's choice of words. Skip for merely referencing an issue, and for reviewing someone's issue body yourself, which is `issue-reviewer`."
---

# Issue workflow

## This flow is GitHub-only

Everything below is `gh issue` and GitHub's own labels, assignees and linked-PR
fields, so on another forge it cannot run. **Judge the host of the repo the
issue lives in, which is not always where you are standing**, from the most
specific input you have:

1. **An issue named by full URL**: the host is in the URL, so read it there and
   stop, without consulting the working directory.
   `https://github.com/dbaggott/claude-plugins/issues/23` is GitHub even from a
   GitLab checkout, and `https://gitlab.com/acme/api/-/issues/7` is GitLab even
   from a GitHub one.
2. **A bare issue number, or creating an issue in place**: the input carries no
   host, so the issue belongs to the repo you are in. Only here, fall back to
   reading it:

   ```bash
   git remote get-url origin
   ```

Route 1 is the common path, since issues are referenced by full URL.

**If the host you resolved is not `github.com`, stop and decline.** Say that
this flow is GitHub-only, name the host you found, and fall back to the issue
tracker that project already uses. Make no `gh` call against it, and don't
translate the flow to `glab` or another tracker's CLI.

Not a decline, and reachable only on route 2: a repo with **no `origin`** makes
no forge claim, so proceed and let the operator direct rather than assuming a
host; with **several remotes**, `origin` decides, as the enforcement hooks do.

## Separate paths, and they need different things

Filing an issue, defending one under review, and resolving one are separate tasks
with almost no overlap, so each lives in its own file. Read the one you are on:

- **Creating or updating an issue** → `references/creating.md`. Self-documenting
  bodies, verified anchors, and whether it is a project;
  labels are `references/labeling.md`; the filing command and the spec review
  offered after it are `references/filing.md`. Keeping a body current as work ships is
  "Maintaining issues" below, since it fires on every path.
- **Decomposing an accepted tracking issue into children** →
  `references/decomposing.md`. Grouping requirements, the `Covers` and
  `Depends on` lines, and setting sub-issue and blocked-by relationships.
- **Answering a review of the issue body itself** → `references/spec-review-rounds.md`.
  Responding per finding ID, the edit-then-comment ordering the reviewer reads
  your state from, and waiting on the next round
  (`references/spec-review-wait.md`). The reviewer's side is the
  `issue-reviewer` skill.
- **Picking up an issue to resolve it** → `references/claiming.md` first:
  checking it is not already claimed, asking once when it belongs to a
  project (`references/project-pickup.md`), then claiming it. Then
  `references/resolving.md`: the freshness probe, the critical review of the
  issue itself, and the link-following discipline.

**On pickup, read `references/claiming.md` before touching any file or
opening a worktree.** Claiming comes first, and an issue already being worked by
someone else is a stop, not a merge conflict to discover later.

Everything below applies to both.

## Writing as the author

Every issue write this skill has you make goes up as the **author role**:
filing an issue, editing its body or labels, commenting, claiming, minting a
label. Each runs through the role resolver, with any body drafted in your
draft directory (`<skill-dir>/../git-workflow/references/draft-files.md`):

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
  gh issue edit <n> --repo <owner>/<repo> --body-file <file>
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
  gh issue comment <n> --repo <owner>/<repo> --body-file <file>
```

`<skill-dir>` is this skill's Base directory. Reads run under your own auth.
The stderr line, `as-role.sh: result=OK as=<login>
fallback=<none|unconfigured>`, says whom it ran as. On `result=ERROR` nothing
ran, so do what it prints; a `credential` refusal is an App that is set up and
could not mint, so fix what it names. Never make the write another way. The
write scripts take the role as a flag instead
(`claim-issue.sh --as=author`). `git-workflow`'s "Acting as the author" carries
the resolver in full.

## Maintaining issues

The cheapest sweep is the one never owed — write state-independent references (`references/creating.md`) and most of this section never triggers. For the drift that remains:

**The body is the current truth; comments are history.** A cold resolver reads the body as "this is the work," so a body that has drifted from reality actively misleads — and no comment thread repairs that, because resolvers under the link-following discipline in `references/resolving.md` won't reconstruct truth from a comment archaeology dig.

This isn't a standing patrol duty. The trigger is touching the issue for any reason — commenting on it, shipping part of it, closing or merging a PR it references. For the merge case, find the issues to sweep via `gh pr view <n> --json closingIssuesReferences` (the keyword-linked set), any issue URLs in the PR description, and the open issues each closed issue blocks, whose bodies were written before this merge and may still ask for what it shipped, read with the closed issue's own owner, repo and number, taken from its URL, since it may live in another repo than the PR:

```bash
"<skill-dir>/../../scripts/issue-blocking.sh" <owner>/<repo> <closed issue>
```

`result=OK` comes after the URLs of the open issues it blocks, one per line, and `count=0` with none is a complete answer: the issue blocks nothing open. Any `result=ERROR` prints no URLs, so that part of the sweep is incomplete, not empty: name the reason in your report rather than counting the sweep done. `bad-args` and `unsupported-forge` mean the script refused before any read, `not-found` that the number names no issue, `issue-query` and `issue-query-shape` that the read failed or stopped parsing, and `set-overflow` that the issue blocks, open or closed, more issues than one page holds, so the list would have been truncated.

This sweep is maintenance, not context exploration, so the depth-1 reading cap in `references/resolving.md` doesn't apply to it (it is stated there; you do not need to load that file to take this exemption). A swept issue someone else has claimed (`claim-issue.sh` reads `FOREIGN`, per `references/claiming.md`) is its holder's to edit: comment what shipped there instead (as the author, per "Writing as the author"), for the holder to fold into the body. So is a tracking issue whose children are being worked, unless you orchestrate it (`references/tracking-issue.md`, "Who writes the body"). When triggered, bring the body back to current truth before moving on, with the body edit in "Writing as the author":

- **Status-mark shipped work.** If part of the issue has landed, mark that section shipped (with the PR URL) instead of leaving it presented as open work — otherwise a cold resolver re-implements it.
- **Promote comment-borne facts into the body.** New evidence or decisions that arrived as comments get folded into the body. A fact that lives only in a comment is invisible to the handoff.
- **Sweep cross-references on state changes.** When a referenced PR or issue closes or is superseded, update the body text that depends on it — a "how to apply" that names a mechanism from a closed PR sends the resolver hunting for a file that doesn't exist.

**A plain issue that has grown** until a test in `references/creating.md`, "Is this one issue or a project?", fires: ask with `AskUserQuestion` once per issue, recording the answer as a comment on it (the comment command in "Writing as the author"), with two options. **"Rewrite as a tracking issue"** rewrites its body and title in place per `references/tracking-issue.md`; **"Leave as is"** keeps it a plain issue, and the recorded answer stands for later touches. Without `AskUserQuestion`, leave it as is and say in the report which test fired.

## Referencing issues and PRs

Full GitHub URLs, always, per the always-on rule "Reference issues and PRs by
full URL". From a bare number of unknown type, build the `/issues/N` path:
github.com redirects `/issues/N` and `/pull/N` to each other.

## Related skills

Optional: if your project has no coding standards of its own, the separate
`dnbg-practices` plugin carries them (`/plugin install dnbg-practices@dnbg`).
