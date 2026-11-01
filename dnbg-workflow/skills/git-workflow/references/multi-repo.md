# Git workflow: multi-repo changes

Part of the `git-workflow` skill. Read this before picking the branch name when
a change spans repos, and when a change turns multi-repo midway, before opening
the next repo's PR. `SKILL.md`'s "Project tag" covers a PR tagged for a
tracking issue.

When one logical change spans repos (e.g. an infrastructure change plus the application change it enables), pair the PRs so a list view shows what goes with what:

1. **Same branch name in every repo.** Pick the branch name once and reuse it verbatim for each repo's worktree. It's the join key: it exists before any PR does (no ordering problem), it shows in `gh pr list`, and `gh search prs --owner <owner> head:<branch-name>` returns the whole set.
2. **Shared title tag.** Prefix every sibling PR's title with the branch name in brackets — `[<branch-name>] <title>`. github.com's PR list doesn't show branch names, so the tag is what makes the pairing visible there. The tag *is* the branch name, not a separate slug — one join key, derivable in both directions.

3. **Every sibling references the issue by full URL; exactly one closes it.** When the set resolves an issue, put the issue URL in *each* PR's body — the sibling's opening line is a good home ("The infrastructure half of `<issue URL>`"). Only the PR that actually completes the work carries a closing keyword (`Closes <issue URL>`); the others just mention it.

   The mention is the only thing that makes a sibling discoverable from the issue — every route back to it is driven by the mention, so a sibling that omits it cannot be found from the issue at all, and anyone working from that issue sees a set that looks complete and is not. The branch name pairs the PRs to each other; the issue URL ties the set to the issue. Both are needed.

Single-repo PRs (the common case) stay untagged, apart from the project tag in `SKILL.md`'s "Project tag" — a tag that is a branch name is itself the signal that siblings exist in other repos.

If a change turns multi-repo midway — the first PR is already open when you discover a second repo needs to change — reuse its branch name for the new worktree and retitle the open PR to add the tag (`"<skill-dir>/../../scripts/as-role.sh" author <repo> -- gh pr edit <num> --repo <repo> --title "..."`), replacing any project tag (`SKILL.md`'s "Project tag"), when you open the sibling.
