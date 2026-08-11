# Requirements

**Claude Code v2.1.207 or newer.** The manifest format has no field for a
minimum version, so this is documented rather than enforced — nothing stops an
older client installing the plugin and misbehaving quietly. Verified working on
v2.1.226. ([Where the floor comes
from](maintainers.md#where-the-version-floor-comes-from), if you need it.)

**Command-line tools.** Not all of them are needed for all of it — the first two
are what the enforcement hooks run on, and the last three only matter if you use
the reviewer bot:

| Tool | Needed for | Without it |
| --- | --- | --- |
| `jq` | Both enforcement hooks parse their stdin payload with it | **Enforcement is off.** Ships with macOS 15+; install it on Linux and on older macOS |
| `git` | `check-worktree.sh` resolves the edited path to a repo | **`check-worktree` never fires**; `check-issue-create` still gates a `--repo`-qualified command |
| `gh` | Every workflow skill, for all PR/issue/review operations | The skills cannot run |
| `python3` | `reviewer-setup`'s `bootstrap.py` (stdlib only) | Cannot create the reviewer App |
| `openssl` | `mint-token.sh` signs the App JWT locally | Cannot mint a reviewer token |
| `curl` | `mint-token.sh` exchanges that JWT with GitHub | Cannot mint a reviewer token |

The two hooks **fail open**, so a missing `jq` or `git` does not block your work
— it silently stops protecting it. Claude Code classes a hook exiting non-zero
and non-2 as a non-blocking error: the edit proceeds, you get a `hook error`
notice naming the missing binary, and *Claude does not see that notice at all*,
so the agent goes on believing the gates are live. `inject-rules.sh` therefore
checks at session start and says so once, in output both you and Claude can see.

`mint-token.sh` checks for its own three and exits with a clear message, so
those fail loudly at the point of use rather than needing a session-start
warning.

**Platform: macOS and Linux.** Both are exercised. The hooks are `#!/usr/bin/env
bash` scripts invoking only `cat`, `dirname`, `git`, `grep`, `head`, `jq`,
`printf`, `sed` and `tr` — all local text or path processing. They are expected
to work under Git Bash on Windows, but that has never been tested and is not
claimed.
