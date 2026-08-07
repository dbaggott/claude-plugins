The plugin no longer updates itself. `update-marketplace.sh` has been removed,
along with its session-start hook — the plugin now makes no network access at
all, and what you install is what runs until you update it.

Claude Code's own per-marketplace auto-update does the same job and does it
sooner: it checks after each session starts rather than throttling to once every
four hours.

## Migration
Nothing breaks, but **you will stop receiving updates automatically** unless you
turn them on. In `/plugin` → Marketplaces → dnbg → Enable auto-update. The
removed hook also left a throttle stamp behind; delete it if you like:

    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/dnbg-workflow/last-update"
