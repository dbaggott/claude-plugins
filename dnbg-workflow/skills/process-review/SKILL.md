---
name: process-review
description: Read a batch of the retrospectives that `orchestrate` runs leave behind, report the process patterns in them with counts and quoted examples, and draft upstream issues for the operator to approve. Load when asked to review the retrospectives, find process patterns, or say what keeps slowing the agents down. Skip for writing a retrospective, which is `orchestrate`'s `references/retrospective.md`, and for disposing of a tracking issue's friction log at closeout, which is `orchestrate`'s `references/closeout.md`.
---

# Process review

A retrospective records where the process hurt one agent on one issue, and one
file is an anecdote. This finds what recurs across many, and drafts an upstream
issue for whatever the shipped tooling is to blame for. It runs cold: everything
it needs is in the files and this page.

The file format, including the four headings this groups by, is in
`orchestrate`'s `references/retrospective.md`, at
`<skill-dir>/../orchestrate/references/retrospective.md`. `<skill-dir>` is the
**Base directory** announced when this skill loads.

## 1. Gather the batch

By default the batch is every `*.md` file under
`~/.claude/dnbg-retrospectives/`, recursively. That root is the default, not a
constant: if a `dnbg-workflow` note at session start names a different
retrospective root, read that one. The operator may name a subset instead: a
repo's `<owner>/<repo>/` directory, a list of files, a date range against the
frontmatter `date`, or one `plugin_version`.

Read every file in the batch in full. A file missing `role` or `issue` in its
frontmatter, or missing any of the four headings, goes under **Unreadable** in
the report with what it lacks, and counts toward nothing.

**Given a tracking issue URL, read its friction log too.** Fetch the body with
`gh issue view <url> --json body` and take the bullets under its **Friction
log** heading. Each bullet is one more source: sort it under whichever of the
four headings fits, and cite it as `friction log <date>`. This step is
GitHub-only; for a URL on another host, say so and review the files alone.

## 2. Find the patterns

Group the items by heading, then within a heading put together the items that
describe one problem: the same skill step, script, or missing instruction, even
when worded differently.

- **The count is the number of sources carrying the problem**, where a source is
  a file or a friction-log bullet. Two items in one file count once.
- **A pattern has a count of at least two.** Everything else is a singleton.
- **One problem under two headings is one pattern.** File it under the heading
  most of its sources use, and count each source once.
- **Note the spread**: the roles, the issues, and the `plugin_version` values.
  When every source predates the current version, read the current text of the
  skill or script before proposing anything, since it may already be fixed. Say
  which you found.

## 3. Report

One section per heading that has anything, patterns in descending count. Each
pattern is a one-line statement of the problem, its count and spread, and two
examples quoted verbatim, each cited by file name:

```markdown
### Worked around

**`claim-issue.sh` reads a resumed session's own claim as `FOREIGN`, and the
agent re-claims over itself.** Count 2: author ×2; 2 issues; 2026.10.3.

> "claim-issue said FOREIGN with my own id after the resume, so I re-claimed."
> (`2026-09-30T101500Z-17-author.md`)

> "Re-claimed over what turned out to be my own claim."
> (`2026-10-02T143000Z-21-author.md`)
```

After the patterns, list the singletons one line each, since the next batch can
make any of them a pattern. Then **Unreadable**, if anything was.

## 4. Draft upstream issues

For each pattern caused by shipped tooling, meaning a skill, script, or hook of
an installed plugin rather than the project's own code or the operator's setup,
draft an issue under the always-on rule "When shipped tooling doesn't fit, tell
the user":

- **The destination** is the `repository` field of the owning plugin's
  `.claude-plugin/plugin.json`.
- **Check for an existing issue first**, with
  `gh issue list --repo <destination> --state all --search "<keywords>"`. When
  one covers the pattern, draft a comment adding the new evidence instead.
- **Write from the generic case.** Leave out repo names, issue URLs, file paths,
  and any quote that identifies the operator's work. Keep the count and the
  substance of the examples.
- **Shape the body** per `issue-workflow`'s `references/creating.md`.

Show the operator each draft's exact text, after the report. File one only once
the operator approves that exact text, and load `issue-workflow` before filing.
An edited draft is new text, which needs approval again. Never file without
that approval. Where `AskUserQuestion` is absent, as in a subagent, report the
drafts and file nothing.
