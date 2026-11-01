An author that `orchestrate` dispatches no longer re-reads the claim reference
at pickup. When its prompt says the issue, or the issues, are already claimed
under its session id, it runs only `claim-issue.sh` for each issue and, when
every one reads `OWN`, goes straight to resolving the issue. Any other claim
result still sends it through the full claim check, as before.
