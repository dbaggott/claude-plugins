---
name: process-review
description: Read a batch of the retrospectives that agents leave behind, report the process patterns in them with counts and quoted examples, and draft upstream issues for the operator to approve. Load when asked to review the retrospectives, find process patterns, or say what keeps slowing the agents down. It reads only the retrospective files and its own past reports, never a tracking issue. Skip for writing a retrospective, which is this skill's `references/retrospective.md`, and for findings about the code, which are `findings-review`'s and a tracking issue's closeout's.
---

# Process review

A retrospective records where the process hurt one agent on one issue, and one
file is an anecdote. This finds what recurs across many, and drafts an upstream
issue for whatever the shipped tooling is to blame for. It runs cold: everything
it needs is in the files and this page.

The file format, including the four headings this groups by, is in this
skill's `references/retrospective.md`, at
`<skill-dir>/references/retrospective.md`. `<skill-dir>` is the **Base
directory** announced when this skill loads.

## 1. Gather the batch

The root is `~/.claude/dnbg-retrospectives/` by default, not a constant: if a
`dnbg-workflow` note at session start names a different retrospective root, use
that one. The batch is drawn from every `*.md` file under the root, recursively,
**except** under `<root>/_reviews/`, which holds this skill's own reports
(step 3). A run is one of three kinds, recorded as its report's `batch`:

- **`delta`**, the default when `_reviews/` holds a report whose `batch` is
  `delta` or `all`. Chain from the newest such report (by file name), ignoring
  subset reports: a subset run has not read the rest, so its reach is no
  watermark. The batch is:
  - every retrospective whose basename starts with a `<YYYY-MM-DD>T<HHMMSS>Z`
    prefix at or after that report's `newest`, comparing that prefix, not the
    full name, the frontmatter `date` or mtime. "At or after", so two files
    written in the watermark's second are not lost;
  - the files cited by that report's **Carried** singletons, so a singleton
    that recurs in the delta becomes a pattern with both sources in hand. A
    cited file that no longer exists goes under Unreadable as missing;
  - the files that report's Carried section lists as **Unreadable**, so a
    repaired file is counted once it reads;
  - any file whose basename has no such prefix: it goes under Unreadable with
    that reason, and so is carried and tried again next run.

  A file in more than one of these is read once. Beyond these, the files of
  carried **patterns** are not re-read; their sources and examples come from
  Carried.
- **`all`**, when `_reviews/` holds no `delta` or `all` report, or when the
  operator names `all`: every file under the root, with nothing carried in.
- **A subset** the operator names: a repo's `<owner>/<repo>/` directory, a list
  of files, a date range against the frontmatter `date`, or one
  `plugin_version`. Its `batch` is what was named. Nothing is carried in.

Read every file in the batch in full. A file missing `role` or `issue` in its
frontmatter, or missing any of the four headings, goes under **Unreadable** in
the report with what it lacks, and counts toward nothing. A file written before
`issue-reviewer` became a role of its own carries `reviewer` for a spec round
as well as for a PR review: it is readable, and counts under `reviewer`.

## 2. Find the patterns

Group the items by heading, then within a heading put together the items that
describe one problem: the same skill step, script, or missing instruction, even
when worded differently.

- **The count is the number of sources carrying the problem.** A source is one
  role on one issue, all its files together. So one agent repeating itself
  counts once.
- **A pattern has a count of at least two.** Everything else is a singleton.
- **One problem under two headings is one pattern.** File it under the heading
  most of its sources use, and count each source once.
- **In a `delta` run, start from the chained report's Carried patterns.**
  Each keeps its carried statement, which is what its Filed line is matched by.
  Match each against the batch's items by that statement and its carried
  examples, and recompute its count over the union of its carried sources and
  the new ones, keyed by `role` plus `issue`: an item from a source already
  listed, such as a re-read singleton file, does not raise it. A carried
  singleton matched by an item from another source becomes a pattern.
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
make any of them a pattern. Then **Unreadable**, if anything was. In a `delta`
run, every carried pattern is in the report whether or not it gained a source:
one left out breaks the chain the next run reads, and a recurrence would count
as a fresh singleton.

Before drafting anything, write the report to
`<root>/_reviews/<YYYY-MM-DD>T<HHMMSS>Z.md`, stamped in UTC
(`date -u +%Y-%m-%dT%H%M%SZ`), so a run abandoned in step 4 still leaves it:

```markdown
---
tags:
  - process-review
date: <YYYY-MM-DD>
batch: <delta, all, or the subset named>
files: <count read>
newest: <the newest basename prefix in the batch, never earlier than the chained report's>
plugin_version: <as retrospective.md's plugin_version step sources it>
---
```

`<root>` is the root step 1 read from. Only a `delta` or `all` run writes
`newest`. The body is the report above, then:

- **`## Carried`**, in a `delta` or `all` run only: the state the next run reads. Every pattern and every
  singleton: its heading, its one-line statement, and its sources, one line per
  source giving `role`, `issue` and the file names it was found in. A pattern
  also keeps its two quoted examples; a singleton does not, since its files are
  re-read. Then the Unreadable file names. In an `all` run it is this run's
  findings alone.
- **`## Filed`**, appended in step 4.

## 4. Draft upstream issues

The **last report** is the newest `delta` or `all` report under `_reviews/`
before this one, whatever kind this run is; in a `delta` run it is the chained
report. Draft only for a pattern that has a source the last report's Carried
does not list, or no decided line in its Filed section: none at all, or
`not filed: no operator (delegated)`. With no last report, every pattern is
drafted. A pattern that gets no draft copies its decided Filed line into this
report's Filed section, so the decision survives the next run.

For each such pattern caused by shipped tooling, meaning a skill, script, or hook of
an installed plugin rather than the project's own code or the operator's setup,
draft an issue under the always-on rule "When shipped tooling doesn't fit, tell
the user":

- **The destination** is the `repository` field of the owning plugin's
  `.claude-plugin/plugin.json`.
- **Check for an existing issue first.** The last report's Filed line for
  the pattern names its issue when one was filed, and the draft is a comment
  adding the new sources. Otherwise search with
  `gh issue list --repo <destination> --state all --search "<keywords>"`, which
  is also what finds an issue a subset run filed. When one covers the pattern,
  draft a comment adding the new evidence instead.
- **Write from the generic case.** Leave out repo names, issue URLs, file paths,
  and any quote that identifies the operator's work. Keep the count and the
  substance of the examples.
- **Shape the body** per `issue-workflow`'s `references/creating.md`.

Show the operator each draft's exact text, after the report. File one only once
the operator approves that exact text, and load `issue-workflow` before filing.
An edited draft is new text, which needs approval again. Never file without
that approval. Where `AskUserQuestion` is absent, as in a subagent, report the
drafts and file nothing.

As each draft is decided, append its line to the report's `## Filed` section:
the pattern's one-line statement, then the issue or comment URL,
`not filed: <the operator's reason>`, or, without `AskUserQuestion`,
`not filed: no operator (delegated)`.

Close with one line naming the report file written.

When any draft was filed as a new issue in a covered repo, one whose owner is in
this plugin's `owners` setting, ask once for those issues, with the two options
of `issue-workflow`'s `references/filing.md`, "Offer the spec review", in place
of its per-issue question. A draft filed anywhere else is a gap reported
upstream, and a comment on an existing issue is not a new one: neither is
offered. The prompt is `Review <URL>, <URL> as a set.`, one per repo, naming
that repo's issues. On "Spec-review it now (Recommended)", dispatch
`issue-reviewer` as `dnbg-workflow:reviewer-orchestrated` with each prompt, in
the background, and answer the rounds per `issue-workflow`'s
`references/spec-review-rounds.md`, "Spawn the reviewer". On "Not now", end with
the prompts to paste.
