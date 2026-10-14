`issue-reviewer` now reads a later round's changes from the issue's own edit
history on GitHub, rather than from a copy of the body it had to keep itself. A
round no longer depends on the session that wrote the last one still holding that
copy. The same history is available to you: `scripts/issue-diff.sh` in the
`dnbg-workflow` plugin prints a unified diff of an issue's body between two times.
