# Changelog fragments

One file per pull request, describing what changed for a **user of the plugin**.
The release workflow folds them into `CHANGELOG.md` and the GitHub Release, then
deletes them.

```
changelog.d/<plugin-name>/<short-slug>.md
```

`<plugin-name>` must match a `name` in `.claude-plugin/marketplace.json`. The
directory *is* the attribution — there is no front-matter field naming the plugin.

## Fragments drive releases

A plugin with pending fragments is released; a plugin without them is not — so a
whitespace fix carries none and correctly burns no version.

The corollary is worse than a missing release note: **a change merged without a
fragment is never delivered to anyone who already installed the plugin.** The
version is Claude Code's update cache key, so no bump means no update, and the
change sits on `main` invisible to existing installs until some later release of
that plugin happens to carry it along.

CI enforces it: the changelog step in `ci.yml`'s `lint` job fails any PR that
touches a plugin's directory without adding a fragment.

**The escape hatch is the `no-changelog` label**, for changes with genuinely no
user-visible effect — a comment fix inside a skill, a CI tweak that happens to
touch a plugin directory.

## Format

Plain Markdown, no front-matter.

**Write an executive summary for someone deciding whether this release affects
them.** They have not read the diff. Two or three short paragraphs is the normal
size; one sentence is often right. Past a screen, you are arguing rather than
reporting.

```markdown
Fixed every review posting under your personal GitHub account instead of the
reviewer bot. The failure was silent, since posting as yourself succeeds on a PR
you did not write.
```

### Say what changed

Every entry answers one of these:

- **New capability** — what you can now do, or a new option and where to set it.
- **A bug fixed** — what went wrong from the outside, and what happens now.
- **Behavior that changes under you** — what the hooks block, what an always-on
  rule says. These land as soon as the plugin updates.
- **Cost** — a skill that loads less, or a flow that spends fewer API calls. Say
  roughly how much.
- **A guarantee you can now rely on** — a case that used to be undefined.

A change answering none of these may belong under `no-changelog` instead — but
that label is what stops the release, so read "Fragments drive releases" above
before reaching for it. Difficulty writing the entry is not evidence there is
nothing to say: a refactor that shrinks a skill reads as internal and is **Cost**.

### Leave out

- **Internal names** — script filenames, tests, functions, result codes, argument
  spellings. Name the skill or the user-visible surface instead: `reviewer`, "the
  PR watch", "the worktree hook".
- **The investigation** — how the defect was found, what the root cause was
  internally.
- **The design argument** — why this shape and not another. Put it in the PR.
- **What did not change**, unless a reader would fear it did.
- **Counts of the work** — lines, files, markers, tests. Nobody acts on them, and
  rounding does not save them.

Keep a value the reader acts on: a version floor to check an install against, a
path to run, a setting to change, the size of something they now load. State it
loosely enough to survive the next commit — a fragment is written while the
change is still moving, so an exact count is falsified by a later commit and
caught by a reviewer spending a round on it.

### Migration

Add a `## Migration` section **only when the user has to do something** — it is
published verbatim in the release notes, so a section there implies an action. A
rename inside the plugin, where the skills were updated in the same release, is
not one.

```markdown
## Migration
Repos opting in via `CLAUDE.md` must change `dnbg-workflow:old-name` to
`dnbg-workflow:new-name`. The old name silently stops loading.
```

### Before you commit it

Read it as someone who has never opened this repo, and cut any sentence that only
lands for someone who read the diff. The entry is done when a reader can tell
whether the release affects them — not when it accounts for the work.
