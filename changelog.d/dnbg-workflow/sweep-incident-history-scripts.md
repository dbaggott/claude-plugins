Finished trimming the incident history out of `dnbg-workflow`, sweeping the
`scripts/` and `hooks/` comment blocks the earlier pass left behind. Every guard,
contract and result code is unchanged — what went is the narration of the defects
that prompted them, which `coding-practices` bans. `watch-pr.sh` also states the
fail-closed-and-silent rationale once and points its other fetch/parse splits at
it, rather than restating it at each.
