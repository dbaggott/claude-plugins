`pr-sources.sh` now prints each PR's state (`state=OPEN`, `MERGED`, `CLOSED`, or
`unknown` when the PR could not be read) on its result line. The skills that find
an issue's PRs filter on it instead of running `gh pr view` on every hit, so an
issue with a long history of merged or unrelated PRs costs one call instead of
one per PR.
