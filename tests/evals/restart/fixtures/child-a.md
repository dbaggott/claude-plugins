Sub-issue of {{PARENT}} (the design). Section IDs below refer to that body.

**Covers:** R1
**Depends on:** none

### Problem

`restart-eval/{{RUN}}/name.txt` does not exist.

### Proposed approach

Add the file with the single line `restart eval`, in one commit on a branch of its own.

### Acceptance criteria

- On the PR's head, `restart-eval/{{RUN}}/name.txt` holds the single line `restart eval`, newline-terminated.
- The PR changes no other file.

### Required reading

- Parent: C1, R1, D1.
