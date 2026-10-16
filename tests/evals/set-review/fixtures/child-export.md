Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R0, R1
**Depends on:** none

### Problem

There is no sample `notes/` to work against, and no machine-readable form of the notes.

### Proposed approach

Add the sample `notes/` R0 describes. Add `scripts/export.sh [dir] [out]`, with R1's defaults. For each `<dir>/*.md`, take the slug from the filename, the title from the first line with its `# ` stripped, and the body from everything after the blank line that follows it. A file not in R0's form, its name included, is an error: the script names the file and exits 1 without writing `out`. Build the object with `jq -n`, so quoting is `jq`'s job and not the script's, sort `notes` with `sort_by(.slug)` per D2, and write it to `out`.

### Acceptance criteria

- `scripts/export.sh` run on the sample `notes/` writes `export.json` matching R1's shape, with the notes in bytewise slug order, `a` before `a-b`.
- The sample note whose body contains a double quote and a backslash survives into the JSON unchanged.
- Run on a copy of the sample with one more note named `Bad.md`, and again with one note's blank second line removed, it exits 1, names that file, and writes nothing each time.

### Required reading

- Parent: C1, R0, R1, D2.
