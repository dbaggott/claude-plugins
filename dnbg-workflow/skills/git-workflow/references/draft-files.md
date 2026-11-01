# Git workflow: draft files

Part of the `git-workflow` skill. Read this before you draft your first PR
description, issue body, comment or review in a file, and before you dispatch
an agent with the Agent tool. Every skill that has you draft a body sends you
here.

Every PR description, issue body, comment and review you draft in a file before
posting it goes in **your draft directory**, under a fixed name for its purpose:
`pr-body.md`, `issue-body.md`, `comment.md`, `review.md`, numbered when two of
one purpose are drafted at once, such as a review's inline comments
(`inline-1.md`, `inline-2.md`). Only you write the directory, so a fixed name
cannot collide with another agent's draft, and you find a draft again by its
name. Never find one by listing the scratchpad: a dispatched agent shares its
dispatcher's, and the newest file there may be a sibling's.

- **Which directory.** The one your prompt names on its `Your draft directory:
  <path>` line. When nothing names one, as in a session nobody dispatched,
  create it at your first draft with `mktemp -d <scratchpad>/drafts.XXXXXX`
  (plain `mktemp -d` when the harness names no scratchpad directory), and state
  its path in your next message, so it stays in your context across Bash calls.
  If you lose the path, create another the same way rather than look for it.
- **Before writing a draft**, run `mkdir -p <draft directory>`: the harness's
  scratchpad can vanish mid-session.
- **Posting one**: check it is non-empty first (`test -s <file>`), stopping
  rather than posting an empty body, and delete it once it is posted (`rm
  <file>`). A fixed name is reused next round, so a draft you failed to rewrite
  would otherwise post last round's text. To change a posted body, read it back
  from GitHub.
- **Round files**: a review watch you arm with `--round-dir=<draft directory>`
  writes each round it fetches there as `pr-round-*`. Delete one (`rm <file>`)
  once you have handled its round.

**When you dispatch an agent** with the Agent tool, create its directory first,
`mktemp -d <scratchpad>/<role>-<n>.XXXXXX`, where `<role>` is `author` or
`reviewer` and `<n>` the number of the issue or PR it works on (the first, for a
set), and end its prompt with the line `Your draft directory: <path>`.
