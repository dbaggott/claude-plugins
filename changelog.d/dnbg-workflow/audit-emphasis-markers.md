Audited every `⚠️` marker in the repo against the emphasis budget, rather than
only the one file `watch-pr.sh` was rebalanced in. 91 markers across 25 files;
61 remain.

Each was kept or demoted on the stated test — does it mark a silent failure of
the reserved kind — not against a per-file quota. What goes defends a design
decision ("X is load-bearing, not tidiness"), routes the reader somewhere, or
warns about something that fails loudly. What stays names a way the system goes
wrong without saying so: a zero interval turning a watch into a busy loop around
`gh`, a foreground nap swallowing SIGTERM, a key reaching `openssl` through a
temp file, a discovery set that is empty because a source died, a test run
writing into the developer's real trace directory.

`mint-token.sh` is unchanged. All four of its markers are credential handling,
which is the category the rule reserves them for.
