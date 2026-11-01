# Git workflow: diffs exempt from the defect pass

Part of the `git-workflow` skill. Read this at step 7 when every hunk of the
diff may be generated or data files, prose no agent follows, or a rename the
issue specifies in full, before you skip the code-review tool. `SKILL.md`'s
step 7 carries the rest of the self-review.

The standards pass is the whole stage when every hunk of the diff is one of these:

- **Generated or data files** with no logic in them. Config a program acts on, such as hook matchers or CI conditions, is logic.
- **Prose no agent follows as instructions**, such as a user-facing README or a changelog fragment. Prose that instructs an agent is logic: a SKILL.md and its references, a rules file, an agent definition, a CLAUDE.md, and any file one of those sends an agent to for what to do, such as a CONTRIBUTING.md.
- **A rename the issue specifies in full**, in any file, as long as each hunk only swaps the old name for the new one or rewraps the line it lands on. Its standards pass checks that the new name was not already taken, and greps the tree for the old one, which may stay only in released history such as CHANGELOG.md.

Size alone never qualifies. When you skip the defect pass for these, the PR description that says so names the files for generated, data or prose hunks and the issue for a rename.
