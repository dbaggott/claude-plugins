The reviewer bot's credentials move from `~/.config/agent-reviewer/` to
`~/.config/dnbg/reviewer/`, so everything this marketplace writes to disk now
lives under one `dnbg` directory. The override environment variable is renamed
`REVIEWER_CONFIG_DIR` -> `DNBG_REVIEWER_CONFIG_DIR`.

The GitHub App itself is **not** renamed. It stays `agent-reviewer-<your-login>`,
because it is your identity on other people's pull requests rather than
something this marketplace owns.

## Migration
If you have already set up the reviewer bot, move its directory:

    mkdir -p ~/.config/dnbg && mv ~/.config/agent-reviewer ~/.config/dnbg/reviewer

Nothing reads the old location any more. There is no compatibility fallback, and
none is needed: `mint-token.sh` already fails with `reviewer bot is not set up
(no credentials in <dir>)` naming the directory it searched, so an unmigrated
install says exactly what is wrong instead of failing silently.

If you set `REVIEWER_CONFIG_DIR`, rename it to `DNBG_REVIEWER_CONFIG_DIR`.
