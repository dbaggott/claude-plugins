# Writing a summary file

Part of the `summary-review` skill. Read this when you write or update a summary
file, or file an issue from one. `<summary_dir>` is the directory `SKILL.md`, "The
summary directory", resolves.

## Where it goes

`<summary_dir>/YYYY-MM-DD-<topic>.md`, where the date is the day you write the
file and `<topic>` is a lowercase-dashed slug. Create the directory if it is
missing. Files that belong to the summary, such as images, go in a directory
beside it with the same stem: `<summary_dir>/YYYY-MM-DD-<topic>/`.

When a file with that name already exists, overwrite it, folding any prior
content worth keeping into the new file, for example as a "History" section. Use
a `-v2` suffix only when keeping both versions side by side is the point, such as
a superseded approach worth referring back to.

## The frontmatter

```yaml
---
tags:
  - agent-summary
  - design-proposal
status: superseded
status_ref: https://github.com/<owner>/<repo>/issues/<n>
---
```

- **`tags:`** always holds `agent-summary`, which is how the sweep tells a summary
  from any other file. Add a kind tag saying what the file is for, such as
  `outstanding-work`, `research`, `design-proposal`, `reference` or `issue-draft`;
  the list is open, and a new kind needs no change anywhere. Add a project or
  area tag when the file covers one.
- **`status:`** says whether the file is still needed, one of the three below.
- **`status_ref:`** holds the pointer a `superseded` status takes. It is a key of
  its own because `status: superseded: <URL>` is not valid YAML, and one invalid
  value makes a frontmatter reader drop the whole block, `tags:` with it.
- **`kept:`** is a `YYYY-MM-DD` date the sweep writes when the operator keeps an
  old file. Leave it to the sweep.

| `status:` | `status_ref:` | Meaning |
| --- | --- | --- |
| `active` | none | still needed, as a working copy or as a reference |
| `superseded` | the replacing summary's file name, or the URL of the issue it was filed as | something else is now the record |
| `retired` | none | no longer needed, whether abandoned or done to the extent wanted |

## Setting the status

- **A new summary** is `active`.
- **When a new summary replaces an old one**, set the old one to `superseded`,
  with the new file's name in `status_ref:`, in the same turn.
- **When an issue is filed from a summary's text**, set that summary to
  `superseded`, with the issue's URL in `status_ref:`, in the same turn. The
  issue body is now the version that gets kept current.
- **When the operator says a summary is done with**, set it to `retired` and
  remove any `status_ref:`.

Change only these keys when updating a status; the rest of the file stays as it
is.
