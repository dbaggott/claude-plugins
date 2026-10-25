Agent roles now get their GitHub identity through one resolver,
`scripts/as-role.sh`, in place of the reviewer's hand-exported `GH_TOKEN`. Each
role is data under `roles/<role>/` with its own App, config directory
(`~/.config/dnbg/<role>/`) and `DNBG_<ROLE>_*` variables; the reviewer is the
only role so far, and an existing reviewer setup keeps working with no re-setup.
`reviewer-setup` can create Apps for several roles in one run.

The reviewer's and issue-reviewer's writes, including issue mode's "acting as
reviewer" comment, now post through the resolver as the bot, and its watches
take the bot's login from it. `claim-issue.sh` gains `--as=<role>`, which
claims under a role while assigning your own login. A role without an App falls
back to your account only if its data allows it, and a session-start notice
names each one that does; the reviewer never falls back.
