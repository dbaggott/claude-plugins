The orchestrator now posts a decision-log row with one `decision-row.sh` call,
which composes the row's comment, posts it under the orchestrator role, and,
under a tracking issue, appends the parent's decision-log table row that links
it. A re-run reuses an identical comment rather than posting a second, so a
call whose outcome is unknown is safe to repeat.
