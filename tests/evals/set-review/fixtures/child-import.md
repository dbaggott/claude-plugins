Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R3
**Depends on:** {{CHILD_EXPORT}}

### Problem

An export cannot be turned back into notes.

### Proposed approach

Add `scripts/import.sh <file>`. For each element of `notes`, write `<slug>.md` containing `# <title>`, a blank line, then the body, into a fresh directory, and move it over `notes/` only once every file is written.

### Acceptance criteria

- On a copy of `notes/`, export, import into an empty directory, and export again: the two `export.json` files are byte-identical.
- An import interrupted partway leaves the original `notes/` untouched.

### Required reading

- Parent: C1, R3, D2.
