Fixed `issue-workflow`'s description being cut off at `#245`, which YAML read as
the start of a comment. Everything after it never loaded, including the trigger
to load the skill before reading any file or opening a worktree on issue pickup.
The full description now loads.
