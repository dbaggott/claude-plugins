Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R2
**Depends on:** none

### Problem

Nothing catches a malformed export before someone imports it.

### Proposed approach

Add `scripts/check-export.sh <file>`. One `jq` program validates the whole file: a top-level `notes` array whose every element has exactly the string keys `slug`, `title` and `body`, each slug in R0's form and each title one line, with slugs unique and in bytewise order, which is `jq`'s own string order (D2). On failure it prints the index and slug of the first offending element and exits 1.

### Acceptance criteria

- Run against the `export.json` that `scripts/export.sh` writes for the sample `notes/`, `check-export.sh` exits 0.
- Run against copies of that file with one note's `title` removed, with two notes swapped, with a slug of `../x`, and with a newline in a title, it exits 1 and names the offending note each time.

### Required reading

- Parent: R0 (the slug and title form), R1 (the shape), R2, D2.
