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

Plain Markdown, no front-matter. Write for someone reading release notes, not
for someone reading the diff.

```markdown
Renamed the velocity skill to `velocity-tradeoff`.

## Migration
Repos opting in via `CLAUDE.md` must change `dnbg-workflow:old-name` to
`dnbg-workflow:new-name`. The old name silently stops loading.
```

Add a `## Migration` section whenever a user has to act. It is published verbatim
in the release notes, and it is the only mechanism that carries author-written
migration steps there.

Call out behavior changes explicitly — anything altering what the hooks block or
what an always-on rule says. Those take effect on an installed machine without
the user doing anything.
