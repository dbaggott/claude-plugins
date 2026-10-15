`coding-practices` now loads at roughly a third of its former size. The body is
an index of rules, each with a stable ID (`C10`, `V3`) that a review finding can
cite instead of restating the rule. The long form moved to references the body
points at, each with the trigger for opening it: the comment bar case by
case, the test for prose that instructs an agent, and the design argument
behind extracting, unifying, and logging. A session that never touches a
comment or a skill file never pays for those.

The skill no longer directs you to the Context7 MCP server for library docs.
The rule is now the general one: read the installed source or fetch current
docs rather than writing a call from memory.

Rules that changed in the pass: the "rule of three" is gone; the test is
whether unifying removes a copy or adds flexibility for an absent requirement.
The emphasis "budget" is now a severity test a marker passes or is removed. A
changed test assertion now needs a stated reason in the PR. Code that cannot be
tested without standing up something unrelated is named as a design signal.
