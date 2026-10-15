Fixed the issue-creation hook blocking every `gh issue create` from a subagent
that had loaded `issue-workflow`, which stopped `orchestrate`'s author agents
from filing follow-up issues. The hook now checks the subagent's own skill
loads, so a subagent is allowed once it has loaded the skill and blocked until
then, whatever the main session loaded.
