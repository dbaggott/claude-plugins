---
name: summary-review
description: Write agent summary files to one directory with a status field, and sweep the stale ones into its archive. Load when asked to write or update a summary file (outstanding work, research, a design proposal, an issue draft, notes to pick up later), when filing an issue from one, or to clean up, sweep, triage or archive the summaries. Skip for a recap of GitHub work, which is `work-summary`, and for findings entries, which are `findings-review`.
---

# Summary review

Agents write summary files, one Markdown file per topic, to a directory outside
any repo. Each file says in its frontmatter whether it is still needed, and this
skill sweeps the ones that are not into `archive/`.

## The summary directory

The summary directory is `${user_config.summary_dir}`. Where that value is
empty, or is still a `${…}` placeholder, the setting is unset: use
`~/.claude/dnbg-agent-summaries`. A value that is neither an absolute path nor
one under `~/`, or that holds a character outside letters, digits and `.` `_`
`-` `/`, is not usable either, since it goes into shell commands: use the
default, and say so in your reply. Expand `~` to your home directory. `<summary_dir>` below means this directory.

## Writing or updating a summary file

Read `<skill-dir>/references/summary.md`, where `<skill-dir>` is this skill's
**Base directory**, and follow it. That covers setting a summary's status when
an issue is filed from it. The sweep below is for when you are asked to clean
up the directory.

## Sweeping the summaries

The sweep reads only the files. It looks up no issue state, since a status says
what the file needs, not what happened to the work.

### 1. Gather the batch

The batch is every `*.md` file at the top level of `<summary_dir>` whose
frontmatter `tags:` include `agent-summary`. A summary's asset directory is the
directory beside it with the same stem. `archive/` is not part of the batch.
Everything else at the top level, such as a dot-directory, a file without the
tag, or a directory with no summary of its stem, goes in the report as **not a
summary** and is never moved.

### 2. Classify each summary by its status

Read `<skill-dir>/references/summary.md` first: it defines the statuses and the
frontmatter that step 5 writes. Keep each file's full contents as you read
them, not only its frontmatter: step 5 compares against them.

- `superseded` with a file name in `status_ref:`: **archive** when that file
  exists at the top level or in `archive/`, since an earlier sweep may have
  archived the replacement. When it exists in neither, **keep** the file and
  report the broken pointer.
- `retired`: **archive**.
- `active`: **keep**.
- No `status:`, from before this convention: read the file and propose the
  status whose definition fits, from what the file says about itself: a status
  note at its top, a statement that it is kept as the record or the deeper
  context, or a newer summary that covers the same subject, meaning the same
  `<topic>` slug or one that says it replaces this one, which is `superseded`
  with that file's name in `status_ref:`. Shared tags alone are not enough,
  since one project tag covers many subjects. A word like "shipped",
  "superseded" or "filed" further down describes a part of the work, not the
  file. Quote the line the proposal rests on in the report row. When the file's
  own words point different ways, or nothing settles it, propose `active` and
  call it out as borderline. Classify the file under the proposed status.
- Any other frontmatter, such as a status not listed above, or `superseded`
  with no `status_ref:` or one that is not a file name: **keep** this sweep,
  report it as malformed, and propose a status as for a file with none, which
  step 5 writes so the next sweep classifies the file under it. A `status_ref:`
  holding an issue URL is a `Filed as` note from an earlier rule: read it as
  one at the top of the file, and step 5 writes it as that line.

### 3. Check the age of every kept file

A kept file is an **age candidate** when the date in its filename is more than
60 days before today, and it has no `kept:` date or that date is also more than
60 days before today. A file whose name does not start with a valid
`YYYY-MM-DD` date is a candidate unless its `kept:` date is within 60 days, and
its report row says the name carries no date. Use the filename date, never the file's modification time,
which sync tools change. For each candidate, suggest keep or archive from what
it says, such as open work it still tracks.

### 4. Report

One table, archive rows first, then keep rows, then **not a summary**. Each row
gives the file, its status (marked *proposed* where step 2 inferred it), and a
one-line reason. Mark each age candidate as needing a decision, with your
suggestion. Give every other kept file its age and its last `kept:` date. Call
out a borderline file, such as a stale "What's next" in a spec that is still the
only design record, rather than deciding it silently.

Then ask with `AskUserQuestion`, "Apply the summary sweep?", with two options:

1. **"Apply as proposed (Recommended)"**: "Archive the archive rows, keep the
   rest, and take the suggestion on each age candidate."
2. **"Not now"**: "Nothing is moved or written."

An answer under "Other" that changes rows, such as keeping a candidate or
sending a kept file to archive, approves the table with those changes.

Without `AskUserQuestion`, as in a subagent or a headless session, the sweep
ends at the report: nothing moves, and no `status:` or `kept:` is written.

### 5. Apply what was approved

First check every archive row for a collision: neither the file's name nor its
asset directory's name may already be in `<summary_dir>/archive/`. Check with
`test`, since `mv -n` can skip a move and still exit 0:

```bash
test ! -e "<summary_dir>/archive/<stem>.md" && test ! -e "<summary_dir>/archive/<stem>"
```

When any row collides, stop before writing or moving anything, and report each
collision for the operator to resolve. Otherwise apply the table. Make every
write below with Edit, per `references/summary.md`, "Writing the file". Change
only the `status:`, `status_ref:` and `kept:` frontmatter keys, plus the one
`Filed as` line below, and never delete a file. An archive row's writes wait
until after the comparison in the Archive bullet's first item, so the sweep
never mistakes its own Edit for another writer's. When the file tools refuse
one of the sweep's Edits because the file changed, skip the rest of that row,
and report it as changed during the sweep, naming any of its writes that had
already landed, rather than applying the write again.

- **An age candidate kept**: write `kept: <today>`, as `YYYY-MM-DD`.
- **An age candidate or kept file sent to archive**: write `status: retired`,
  remove any `status_ref:`, and archive it.
- **A proposed status**: write it into each file still kept, with its
  `status_ref:`, or removing one the new status does not take. A file being
  archived takes it too, so the archive says why.
- **A removed `status_ref:` that held an issue URL**: add a `Filed as <URL>`
  line naming that URL, placed as `references/summary.md` says, unless the file
  already names the URL in one.
- **Archive** each archive row into `<summary_dir>/archive/`, creating that
  directory if it is missing. For each row, in this order:
  1. Read the file again and compare its contents with what step 2 kept, never
     its modification time. When they differ, another writer changed it during
     the sweep: skip the row, writing nothing to it and moving nothing, and
     report it as changed during the sweep.
  2. Make the row's writes from the bullets above.
  3. Re-run the collision check, then move the file, and its asset directory if
     it has one, with `mv -n`, and confirm each source path is gone. A check or
     move that fails stops the sweep there, with the files already moved and
     the one that failed in the report.

Close with one line per file changed, its path and what was done to it, and one
per row skipped as changed during the sweep.
