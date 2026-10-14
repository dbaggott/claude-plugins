Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R2
**Depends on:** none

### Problem

`restart-eval/{{RUN}}/greeting.txt` does not exist.

### Proposed approach

Add the file with the single line `hello`, as R2 gives it, in one commit on a branch of its own.

### Acceptance criteria

- On the PR's head, `restart-eval/{{RUN}}/greeting.txt` holds the single line `hello`, newline-terminated.
- The PR changes no other file.

### Required reading

- Parent: C1, R2, D1.
