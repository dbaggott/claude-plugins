# Changelog fragments

One file per pull request, describing what changed for a **user of the plugin**.
The release workflow folds them into `CHANGELOG.md` and the GitHub Release, then
deletes them.

```
changelog.d/<plugin-name>/<short-slug>.md
```

`<plugin-name>` must match a `name` in `.claude-plugin/marketplace.json`. The
directory *is* the attribution — there is no front-matter field naming the
plugin, because a mistyped field is accepted silently and misattributes the
entry, while a mistyped directory is visible in the diff and in `ls`.

## Why fragments rather than generated notes

Notes generated from PR titles after a merge are written by nobody and reviewed
by nobody. A fragment lands in the diff alongside the change it describes, so a
reviewer can see whether it is accurate, and it can carry migration steps that a
title cannot.

## Fragments drive releases

A plugin with pending fragments is released; a plugin without them is not. The
fragment is the authored statement that something release-worthy happened, so a
whitespace fix carries none and correctly burns no version.

The corollary matters, and it is worse than a missing release note: **a change
merged without a fragment is never delivered to anyone who already installed the
plugin.** A plugin's version is Claude Code's update cache key — it "skips the
update if it matches what's already installed" — so no bump means no update. The
change sits on `main`, invisible to existing installs, until some later release
of that plugin happens to carry it along. That could be months.

Because the failure is silent and unbounded, it is enforced rather than
suggested: the changelog step in `ci.yml`'s `lint` job fails any PR that touches
a plugin's directory without adding a fragment.

**The escape hatch is the `no-changelog` label**, for changes with genuinely no
user-visible effect — a comment fix inside a skill, a CI tweak that happens to
touch a plugin directory. The release workflow's own PR needs the same exemption
— it edits every released plugin's manifest immediately after consuming that
plugin's fragments — but gets it from its `auto-release/` branch prefix rather
than the label, which would cost a duplicate CI run to apply.

## Format

Plain Markdown, no front-matter.

**Write an executive summary for someone deciding whether this release affects
them.** They have not read the diff, do not know the internals, and are reading a
list of releases rather than this one. Two or three short paragraphs is the
normal size; one sentence is often right. If a fragment runs past a screen, it is
almost certainly arguing rather than reporting.

```markdown
Fixed every review posting under your personal GitHub account instead of the
reviewer bot. The failure was silent, since posting as yourself succeeds on a PR
you did not write.
```

### Say what changed for the reader

Every entry answers one of these. If it answers none, the change is a
`no-changelog` change.

- **New capability** — something you can now do, or a new option and where to set
  it.
- **A bug fixed** — what went wrong *from the outside*, and what happens instead
  now. What you saw, not where the defect was.
- **Behavior that changes under you** — anything altering what the hooks block or
  what an always-on rule says. These take effect as soon as the plugin updates,
  with the user doing nothing.
- **Cost** — a skill that loads less into the session, or a flow that spends
  fewer API calls. Prompt size is charged to the user on every run, so a real
  reduction is a user-facing improvement and belongs here. Say roughly how much.
- **A guarantee the user can now rely on** — a supported case that used to be
  undefined.

### Leave out

- **Internal names.** Script filenames, test files, function and variable names,
  result codes, argument spellings. The reader cannot act on any of them. Name
  the *skill* or the *user-visible surface* instead — `reviewer`, "the PR watch",
  "the worktree hook".
- **The investigation.** How the defect was found, what was tried first, what the
  root cause turned out to be internally.
- **The design argument.** Why this shape and not another, what a reviewer
  objected to, which alternative was rejected. That belongs in the PR, where its
  reader is.
- **What did not change**, unless a reader would reasonably fear it did. "None of
  this changes what a reviewer checks" earns its line after a section about
  cutting review output; "no behaviour changed" after a docs fix does not.
- **Counts of the internals** — files touched, markers removed, tests added.

Keeping a specific number is right when the reader acts on it: a size a session
now costs, a version floor, a path to run. Cut it when it only measures the work.

### Migration

Add a `## Migration` section **only when the user has to do something.** It is
published verbatim in the release notes, and it is the only mechanism that
carries author-written migration steps there — so a note there implies an action,
and one that says "nothing to do" trains readers to skip the section that matters.

A rename inside the plugin, where the skills were updated in the same release, is
not a migration. Say it in the body if it is worth saying at all.

```markdown
## Migration
Repos opting in via `CLAUDE.md` must change `dnbg-workflow:old-name` to
`dnbg-workflow:new-name`. The old name silently stops loading.
```

### Before you commit it

Read the fragment as someone who has never opened this repo. If a sentence only
makes sense to someone who has read the diff, cut it — do not rewrite it for
them. The entry is complete when a reader can tell whether the release affects
them, not when it accounts for the work.
