# claude-plugins

This repo is the source of the `dnbg-*` plugins. The skills under
`dnbg-*/skills/` are the product, so they are held to the same bar as code.

## Coding standards

Load `dnbg-practices:coding-practices` before writing or reviewing anything here.
It governs prose that instructs an agent as well as code, which is most of what
this repo contains — the skills, the always-on rules, and this file are all held
to it.

This repo authors that standard, so a session without the plugin installed reads
it from the tree instead: `dnbg-practices/skills/coding-practices/SKILL.md`.

## How to size a change here

Load `dnbg-workflow:velocity-tradeoff` when sizing a change or deciding whether
to split a PR. claude-plugins is on the velocity side of that skill's
risk/benefit trade.

Per that skill's own framing this is a ratio, not a fact about the project, so
the inputs it weighs can move. **Say something when you notice one of them
moving.** But this opt-in comes out when the operator decides it comes out — not
on an agent's read of the inputs.

## Verifying a change

CONTRIBUTING.md's "You can run CI's checks locally" lists the commands and says
which of them are narrower than the CI step they stand for.
