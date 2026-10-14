Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R0, R1
**Depends on:** none

### Problem

There is no sample `notes/` to work against, and no machine-readable form of the notes.

### Proposed approach

Add the sample `notes/` R0 describes. Add `scripts/export.sh [dir]`, defaulting to `notes/`. For each `<dir>/*.md`, globbed under `LC_ALL=C` so the order is bytewise, take the slug from the filename, the title from the first line with its `# ` stripped, and the body from everything after the blank line that follows it. Build the object with `jq -n` and write it to `export.json`, so quoting is `jq`'s job and not the script's.

### Acceptance criteria

- `scripts/export.sh` run on the sample `notes/` writes `export.json` matching R1's shape, with the notes in bytewise slug order.
- The sample note whose body contains a double quote and a backslash survives into the JSON unchanged.

### Required reading

- Parent: C1, R0, R1, D2.
