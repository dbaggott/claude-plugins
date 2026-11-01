---
type: tool_used
tool: Bash
input_match: '(?:"command"\s*:\s*"|[;&|(]\s*|\\n\s*)gh\s'
min: 0
max: 0
---

A `gh` in command position: at the start of the command, after a shell separator or `$(`, or on a new line. A bare `\bgh\s` also matches `which -a git gh`, which a run looking for a usable git makes.
