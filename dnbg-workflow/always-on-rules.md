## No flattery

Do not say performative things like: "You're absolutely right!",
"Great point!", "Excellent feedback!"

## Verify before asserting

When recommending code that calls an API or asserting how something
behaves, verify it (read the source, check Context7) or explicitly
hedge ("I haven't verified X"). Don't write from memory for APIs
you haven't used recently.

## Coding standards stack

Before writing or reviewing code, load every standard that applies
and hold the work to all of them: the repo's (its `CLAUDE.md`, any
standards doc it names), any the operator points you at, and
`dnbg-practices:coding-practices` when it is installed. Having it
installed doesn't replace the repo's own — where two disagree the
project's own wins, and the rest still applies. Authoring prose
that instructs an agent (a `SKILL.md`, a rules file, a `CLAUDE.md`)
counts as writing code here.

## All file changes in a covered repo go through a PR

A **covered repo** is one whose `origin` belongs to an account listed
in this plugin's `owners` setting. In one of those, any edit to a
tracked file — application code, skills, plugins, docs, configs,
tests, anything that would appear in `git status` — goes through a
worktree + draft PR. Never edit in the main worktree. Load the
`dnbg-workflow:git-workflow` skill before the first
Edit/Write/NotebookEdit call so the worktree/PR flow is in context.

Outside a covered repo this is guidance, not a rule: follow whatever
flow that project already uses.

## Picking up an issue means loading issue-workflow first

If a task names an existing GitHub issue by number or URL —
"resolve #245", "work on <issue URL>" — load the
`dnbg-workflow:issue-workflow` skill and claim the issue before
starting any work, including before opening a worktree. The
trigger is an issue being named, not the user's choice of words
(and those bare forms are *user* phrasing; see the URL rule below
for your own). Orient on the entry action (issue pickup), not the
destination (the file edits the resolution will need) — reaching
for `git-workflow` first because the work ends in edits skips the
claim and the freshness probe.

## When shipped tooling doesn't fit, tell the user

If a script, hook, or procedure this plugin ships doesn't cover
your case, do the narrow thing that finishes the task, then tell
the user what didn't fit and offer to file an issue upstream — the
maintainer asks for these reports, and the destination is the
`repository` field of this plugin's own
`.claude-plugin/plugin.json`. Never file it under the user's
identity without their consent, and only after they approve the
exact text, written from the generic case — no user present means
no filing. `issue-workflow` carries the rest. A hook that *blocks*
you is working as intended — satisfy it, don't route around it.
Never edit the installed copy under `~/.claude/plugins/`:
unreviewed, invisible to everyone else, and gone at the next
update.

## Reference issues and PRs by full URL

On any user-facing surface (chat, issue bodies, PR descriptions,
commit messages, comments), reference a GitHub issue or PR by its
full URL (`https://github.com/<owner>/<repo>/issues/19`) — never
bare `#19` or `<owner>/<repo>#19`. The full URL is the only form
clickable on every surface (raw terminal text needs a scheme) and
the only one unambiguous when copied between repos. Memory files
are the exception — Claude-context, not rendered to users.
