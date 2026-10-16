The reviewer now removes the directories `fetch-tree.sh` extracts PR trees into
when the PR closes, and the script removes its own directory when a fetch fails.
They used to stay in the system temp directory. A tree fetched by a session that
quit before the PR closed still stays there.
