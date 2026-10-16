The reviewer now removes the directory `fetch-tree.sh` extracts a PR's tree into
when the PR closes. It used to stay in the system temp directory, since the
cleanup named only worktrees and clones.
