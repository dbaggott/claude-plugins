---
name: issue-workflow
description: How to create, maintain, and pick up GitHub issues so context survives the handoff to whoever resolves them cold. Load when about to create a GitHub issue (any `gh issue create`), file follow-up work as an issue, update one after partial progress or a referenced PR closing, label one along the type and `area:*` axes, assign or dispatch one to anyone (person or bot), or pick up an issue named by number or URL ("resolve #245", "do issue 245", "work on <issue URL>") — on pickup load this *before* reading any file or opening a worktree, since claiming the issue comes first. Also load before a PR leaves draft when the implementation departed from the approach the issue described. The pickup trigger is an issue being named, not the user's choice of words. Skip for merely referencing an issue.
---

# Issue workflow

An issue is a handoff: the session that creates it has rich context (the conversation, the code just read, the direction just agreed), and the session that resolves it has only the issue body. Whoever resolves it — a fresh interactive session, an automated agent, a human — reads that body cold. The failure modes this skill exists to prevent:

- **Wasted research.** An issue body full of unlabeled cross-references forces the resolver to either follow every link (burning context budget before any code changes) or skip them (and maybe miss the one that mattered).
- **Wrong implementation path.** An issue that was perfectly clear *in the context of its creation* reads as open-ended to a cold resolver, who then picks a different approach than the one everyone had in mind. The resolution should not depend on which agent happens to pick the issue up.
- **Rotted handoff.** The body was accurate at creation, then the world changed — part of the work shipped, a referenced PR closed, new evidence landed in a comment — and a cold resolver faithfully implements stale truth.

## This flow is GitHub-only

Everything below is `gh issue` and GitHub's own labels, assignees, and linked-PR fields, so on another forge it cannot run rather than merely running worse.

**The host to judge belongs to the repo the issue lives in, which is not always where you are standing.** Resolve it from the most specific input you have:

1. **An issue named by full URL** — the host is in the URL, so read it there and stop. `https://github.com/dbaggott/claude-plugins/issues/23` is GitHub even from a GitLab checkout, and `https://gitlab.com/acme/api/-/issues/7` is GitLab even from a GitHub one. **Do not consult the working directory in this case**; it has no bearing on where the issue lives.
2. **A bare issue number, or creating an issue in place** — the input carries no host, so the issue belongs to the repo you are in. Only here, fall back to reading it:

   ```bash
   git remote get-url origin
   ```

The URL case is the common one, not the exception: the always-on rule requires issues be referenced by full URL, so a bare number is the unusual input. Getting the precedence backwards breaks the normal path in both directions — a cwd gate would refuse `work on <GitHub issue URL>` from a GitLab checkout, which is a coherent request that works fine, and would equally wave a GitLab issue URL through from a GitHub checkout straight into the `gh issue view` error cascade this section exists to prevent.

**If the host you resolved is not `github.com`, stop and decline.** Say that this flow is GitHub-only, name the host you actually found, and fall back to whatever issue tracker that project already uses. Don't attempt a `gh` call against it — a clear statement is the entire benefit, and one failing command replaces it with the confusing errors this rule exists to prevent. Don't translate the flow to `glab` or another tracker's CLI either.

Two cases that are **not** a decline, both reachable only on route 2: a repo with **no `origin`** makes no forge claim either way, so proceed and let the operator direct rather than assuming a host; and where **several remotes** exist, `origin` decides, matching the enforcement hooks.

## Two paths, and they need different things

Filing an issue and resolving one are separate tasks with almost no overlap, so
each lives in its own file. Read the one you are on:

- **Creating or updating an issue** → `references/creating.md`. Self-documenting
  bodies, verified anchors, and labels. Keeping a body current as work ships is
  "Maintaining issues" below, since it fires on both paths.
- **Picking up an issue to resolve it** → `references/resolving.md`. Claiming it
  (and checking it is not already claimed), the freshness probe, the critical
  review of the issue itself, and the link-following discipline.

**On pickup, read `references/resolving.md` before touching any file or
opening a worktree.** Claiming comes first, and an issue already being worked by
someone else is a stop, not a merge conflict to discover later.

Everything below applies to both.

## Maintaining issues

The cheapest sweep is the one never owed — write state-independent references (`references/creating.md`) and most of this section never triggers. For the drift that remains:

**The body is the current truth; comments are history.** A cold resolver reads the body as "this is the work," so a body that has drifted from reality actively misleads — and no comment thread repairs that, because resolvers under the link-following discipline in `references/resolving.md` won't reconstruct truth from a comment archaeology dig.

This isn't a standing patrol duty. The trigger is touching the issue for any reason — commenting on it, shipping part of it, closing or merging a PR it references. For the merge case, find the issues to sweep via `gh pr view <n> --json closingIssuesReferences` (the keyword-linked set) plus any issue URLs in the PR description — this sweep is maintenance, not context exploration, so the depth-1 reading cap in `references/resolving.md` doesn't apply to it (it is stated there; you do not need to load that file to take this exemption). When triggered, bring the body back to current truth before moving on:

- **Status-mark shipped work.** If part of the issue has landed, mark that section shipped (with the PR URL) instead of leaving it presented as open work — otherwise a cold resolver re-implements it.
- **Promote comment-borne facts into the body.** New evidence or decisions that arrived as comments get folded into the body. A fact that lives only in a comment is invisible to the handoff.
- **Sweep cross-references on state changes.** When a referenced PR or issue closes or is superseded, update the body text that depends on it — a "how to apply" that names a mechanism from a closed PR sends the resolver hunting for a file that doesn't exist.

## Referencing issues and PRs

Always use the full GitHub URL (`https://github.com/<owner>/<repo>/issues/19`, `https://github.com/<owner>/<repo>/pull/35`) — never bare `#19` or `<owner>/<repo>#35`. Two reasons:

- **Ambiguity.** A bare number only resolves inside the repo it was written in; the same text pasted into chat, another repo's issue, or a summary file points nowhere.
- **Clickability.** Only full URLs are clickable on every surface. Chat's markdown renderer does link `owner/repo#N`, but raw terminal text (`gh pr view` / `gh issue view` output, commit messages) gets only the terminal's URL matcher, which generally requires a scheme. References get copied between surfaces, so the chat-only form degrades in transit.

Nothing is lost on the web side: github.com renders full URLs to its own issues/PRs as the short `#19`-style link automatically.

When constructing a URL from a bare number of unknown type, use the `/issues/N` path — github.com redirects `/issues/N` ↔ `/pull/N` in both directions, so the path segment never has to match the artifact type.

This applies to every user-facing surface — chat, issue bodies, PR descriptions, commit messages, comments. Memory files are the exception (Claude-context, not rendered to users).

## Related skills

Optional — everything above is actionable without them.

- **Your project's coding standards.** The bar this skill holds issue bodies to
  is the same one applied to code; if your project has no standards of its own,
  `dnbg-practices` is a **separate plugin** in this marketplace that carries them
  — `/plugin install dnbg-practices@dnbg`. Nothing here assumes you have it.
