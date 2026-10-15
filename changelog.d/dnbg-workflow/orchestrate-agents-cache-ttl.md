`orchestrate` now dispatches its author and reviewer as this plugin's own agents,
`dnbg-workflow:orchestrated-author` and `dnbg-workflow:orchestrated-reviewer`,
which keep their prompt cache for an hour instead of five minutes. An agent that
resumes after a long review round, CI run or merge wait no longer re-sends its
whole transcript uncached. Writing to the 1-hour cache is billed at a higher rate
than the 5-minute one.

This relies on an experimental Claude Code agent option. A
`subagentPromptCacheTtl` setting or `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`
overrides it, and a Claude subscription in overage stays at five minutes.
