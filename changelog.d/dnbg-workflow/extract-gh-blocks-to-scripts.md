Three `gh`/`jq`/GraphQL blocks that skill prose asked you to run verbatim are now
scripts under `scripts/`, so they are covered by `shellcheck` and by tests rather
than by nothing: `pr-verdict.sh` (is the standing verdict attached to HEAD?),
`pr-sources.sh` (every PR that might resolve an issue), and `pr-threads.sh` (list
or resolve review threads).

Three behaviours the prose copies described but nothing checked are now enforced:
a verdict reversed at the same SHA is not an approval, discovery that loses a
source says so instead of reporting an empty set, and `--mine` matches the
reviewer bot the way GraphQL actually spells its login.
