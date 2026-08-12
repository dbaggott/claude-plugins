`coding-practices` now names four failures specific to prose that instructs an
agent — a `SKILL.md`, an always-on rules file, a `CLAUDE.md`. It already held
that prose to the comment bar; the failures it listed under that bar were all
comment-shaped. The new ones are an argument made twice, the inverse of a
condition the section is already scoped by, a read an earlier step could have
carried, and a branch the deployment never reaches.

The same pass held the file to its own rules, and it was failing four of them:

- It asserted five times what the Claude Code system prompt says — the exact
  "another file's conclusions" failure it warns about, against a document that
  changes between model releases with no signal here. "Two abstraction vices" was
  framed entirely as a corrective to a caution attributed to it. The rules now
  stand on their own.
- "Don't write API code from memory" was stated three times over three sections;
  it is stated once now, with pointers.
- The file's only `⚠️` marked a Markdown-editing hazard, which is none of the
  four categories its own rule reserves the glyph for. The seven-line procedure
  under it is one sentence now, and the file carries no marker.
