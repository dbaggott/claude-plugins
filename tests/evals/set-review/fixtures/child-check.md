Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R2
**Depends on:** none

### Problem

A malformed export is only discovered when an import fails partway, leaving `notes/` half-written.

### Proposed approach

Add `scripts/check-export.sh <file>`. One `jq` program validates the whole file: a top-level `notes` array whose every element has exactly the string keys `slug`, `title` and `body`, with slugs unique and sorted. On failure it prints the index and slug of the first offending element and exits 1.

### Acceptance criteria

- Run against the `export.json` that `scripts/export.sh` writes for the repo's own `notes/`, `check-export.sh` exits 0.
- Run against copies of that file with one note's `title` removed, and with two notes swapped, it exits 1 and names the offending note each time.

### Required reading

- Parent: R1 (the shape), R2.
