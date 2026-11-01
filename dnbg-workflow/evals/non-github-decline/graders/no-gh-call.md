---
type: tool_used
tool: Bash
input_match: '(?:"command"\s*:\s*"|[;&|(]\s*|\\n\s*)gh\s'
min: 0
max: 0
---

A `gh` in command position: at the start of the command, after a shell separator or `$(`, or on a new line. A bare `\bgh\s` would also match `gh` as an argument, as in `which -a git gh`.
