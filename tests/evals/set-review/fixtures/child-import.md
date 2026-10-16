Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R3
**Depends on:** {{CHILD_EXPORT}}

### Problem

An export cannot be turned back into notes.

### Proposed approach

Add `scripts/import.sh <file> <dir>`. Refuse a `<dir>` that exists and is not empty. Before writing anything, refuse a file in which any slug or title is not in R0's form, naming the note. Otherwise, for each element of `notes`, write `<dir>/<slug>.md` containing `# <title>`, a blank line, then the body.

### Acceptance criteria

- Export the sample `notes/`, import it into an empty directory, and export that directory to a second file: the two exports are byte-identical.
- Importing into a directory that already holds a file exits non-zero and leaves that file unchanged.
- Importing a copy of the export with one slug changed to `../x` exits non-zero, names that note, and writes nothing inside or outside `<dir>`.

### Required reading

- Parent: R0, R3, D2.
