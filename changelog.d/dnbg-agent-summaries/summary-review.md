New plugin. Agents' summary files (outstanding work, research, design proposals,
issue drafts) now have a home and a lifecycle: one directory, set with
`summary_dir` (default `~/.claude/dnbg-agent-summaries`), and a `status:` in each
file's frontmatter saying whether it is still needed (`active`, `superseded` or
`retired`). The `summary-review` skill sweeps the directory: it archives what is
superseded or retired into `archive/`, flags files older than 60 days for you to
keep or archive, and moves nothing until you approve.

If your own `CLAUDE.md` tells agents where to write summaries, set `summary_dir`
to that directory and remove the section; the skill replaces it.
