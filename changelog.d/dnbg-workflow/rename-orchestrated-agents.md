`orchestrate`'s agents are renamed to `dnbg-workflow:author-orchestrated` and
`dnbg-workflow:reviewer-orchestrated`, from `orchestrated-author` and
`orchestrated-reviewer`. Claude Code's agent panel truncates a long agent type,
and the old names lost the role to it, so an author and a reviewer rendered
alike. The role now comes first. Anything that dispatches these agents by the
old names must use the new ones.
