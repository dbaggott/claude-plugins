Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R3
**Depends on:** {{CHILD_EXPORT}}

### Problem

An export cannot be turned back into notes.

### Proposed approach

Add `scripts/import.sh <file> <dir>`. Refuse a `<dir>` that exists and is not empty. Otherwise, for each element of `notes`, write `<dir>/<slug>.md` containing `# <title>`, a blank line, then the body.

### Acceptance criteria

- Export the sample `notes/`, import it into an empty directory, and export that directory: the two `export.json` files are byte-identical.
- Importing into a directory that already holds a file exits non-zero and leaves that file unchanged.

### Required reading

- Parent: R0, R3, D2.
