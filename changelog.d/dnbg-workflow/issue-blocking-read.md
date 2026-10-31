Fixed the merge sweep's read of the issues a closed issue blocks. The sweep named
`gh issue view --json blocking` without its shape, so the first `jq` read of it
failed. A new `issue-blocking.sh` lists the open blocked issues and ends on a
result line, and the sweep now treats any `ERROR` from it as an incomplete sweep
rather than an empty one.
