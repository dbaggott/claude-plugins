#!/usr/bin/env bash
# SessionStart hook: refresh the marketplace and update the installed plugin, so
# a machine stays in sync with the latest skills and hooks without anyone
# running an update command.
#
# Claude Code loads plugins when a session begins, so content fetched here
# applies to the NEXT session, not this one. Because nothing in the current
# session depends on it finishing, hooks.json marks it `async` — a hook that
# blocks session start defaults to a 600s timeout, and a slow GitHub call has no
# business holding up a prompt for content that lands next time anyway.
#
# Throttled to once per 4 hours per machine via a timestamp file so it doesn't
# ping GitHub on every session start. Fails silently when offline or when the
# claude CLI is missing — non-blocking is the default Claude Code hook behavior
# for any exit other than 2.

set -u

STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/dnbg-workflow/last-update"
THROTTLE_SECONDS=$((4 * 3600))

mkdir -p "$(dirname "$STAMP")"

if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ $((now - last)) -lt "$THROTTLE_SECONDS" ]; then
    exit 0
  fi
fi

if command -v claude >/dev/null 2>&1; then
  # Errors here are non-fatal: a broken network shouldn't make this script
  # noisy. We still stamp on the way out — if updates are failing persistently
  # (auth gone, repo moved), throttling avoids hammering GitHub from every
  # session of a broken machine. To force a retry sooner, delete the stamp file
  # or run the slash commands manually.
  claude plugin marketplace update dnbg >/dev/null 2>&1 || true
  claude plugin update dnbg-workflow@dnbg >/dev/null 2>&1 || true
fi

date +%s > "$STAMP"
exit 0
