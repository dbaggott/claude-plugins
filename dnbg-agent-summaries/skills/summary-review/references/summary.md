# Writing a summary file

Part of the `summary-review` skill. Read this when you write or update a summary
file, or file an issue from one. `<summary_dir>` is the directory `SKILL.md`, "The
summary directory", resolves.

## Where it goes

`<summary_dir>/YYYY-MM-DD-<topic>.md`, where the date is the day you write the
file and `<topic>` is a lowercase-dashed slug. Create the directory if it is
missing. Files that belong to the summary, such as images, go in a directory
beside it with the same stem: `<summary_dir>/YYYY-MM-DD-<topic>/`.

A name already in `<summary_dir>/archive/` is taken: add a `-2` suffix to the
stem. When a file with that name already exists at the top level, overwrite it, folding any prior
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
status_ref: YYYY-MM-DD-<topic>.md
---
```

- **`tags:`** always holds `agent-summary`, which is how the sweep tells a summary
  from any other file. Add a kind tag saying what the file is for, such as
  `outstanding-work`, `research`, `design-proposal`, `reference` or `issue-draft`;
  the list is open, and a new kind needs no change anywhere. Add a project or
  area tag when the file covers one.
- **`status:`** says whether the file is still needed, one of the three below.
- **`status_ref:`** holds the replacing summary's file name, which a `superseded`
  status takes. It is a key of its own because `status: superseded: <file name>`
  is not valid YAML, and one invalid value makes a frontmatter reader drop the
  whole block, `tags:` with it.
- **`kept:`** is a `YYYY-MM-DD` date the sweep writes when the operator keeps an
  old file. Leave it to the sweep.

| `status:` | `status_ref:` | Meaning |
| --- | --- | --- |
| `active` | none | still needed, as a working copy or as a reference |
| `superseded` | the replacing summary's file name | a newer summary replaces it |
| `retired` | none | no longer needed: abandoned, done to the extent wanted, or carried on in issues |

## Setting the status

- **A new summary** is `active`.
- **When a new summary replaces an old one**, set the old one to `superseded`,
  with the new file's name in `status_ref:`, in the same turn.
- **When an issue is filed from a summary's text, or the text is folded into
  an existing issue's body**, add a line `Filed as <URL>[, <URL>…]` directly
  under the title, or as the body's first line when the file has no title,
  extending the line when one is already there, so it names every issue the
  text went into. Then, in the same turn, set the summary to `retired` when the
  issues now carry everything the file did, or leave it `active` when the file
  keeps content the issues point back to, such as the research behind them.
- **When the operator says a summary is done with**, set it to `retired` and
  remove any `status_ref:`.

Change only these keys, and the `Filed as` line, when updating a status; the
rest of the file stays as it is.
