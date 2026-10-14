Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R1
**Depends on:** none

### Problem

There is no machine-readable form of the notes under `notes/`.

### Proposed approach

Add `scripts/export.sh`. For each `notes/*.md` in slug order, take the slug from the filename, the title from the first line with its `# ` stripped, and the body from everything after the first blank line. Build the object with `jq -n` and write it to `export.json`, so quoting is `jq`'s job and not the script's.

### Acceptance criteria

- `scripts/export.sh` run on a directory of three notes writes `export.json` matching R1's shape, with the notes in slug order.
- A note whose body contains a double quote and a backslash survives into the JSON unchanged.

### Required reading

- Parent: C1, R1, D2.
