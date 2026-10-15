Fixed an orchestrator and its subagents overwriting each other's PR
descriptions. They share one scratchpad directory, so two agents drafting a
body at the same chosen name, such as `pr-body.md`, could publish one PR's
description onto another. Every skill that writes a PR description, issue body,
comment or review through a file now has it created with `mktemp`, and a test
checks the skills' body-file commands for it.
