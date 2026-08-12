`coding-practices` now names four failures specific to prose that instructs an
agent — a `SKILL.md`, an always-on rules file, a `CLAUDE.md`. It already held
that prose to the comment bar; the failures it listed under that bar were all
comment-shaped. The new ones are an argument made twice, the inverse of a
condition the section is already scoped by, a read an earlier step could have
carried, and a branch the deployment never reaches.

The file also now meets those rules itself:

- Its guidance stands on its own rather than on claims about what the Claude
  Code system prompt says — five of those are gone, including the framing of
  "Two abstraction vices", which read as a corrective to a caution attributed to
  a document that changes between model releases.
- "Don't write API code from memory" is stated once, with pointers, instead of
  three times over three sections.
- No warning marker: the only one sat on a Markdown-editing hazard, which is
  none of the categories its own rule reserves the glyph for. The rule under it
  survives as one sentence.
