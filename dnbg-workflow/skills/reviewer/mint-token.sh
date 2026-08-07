#!/usr/bin/env bash
# Mint a short-lived (1-hour) GitHub App installation token for the local
# reviewer bot, and print it to stdout. Use it as `GH_TOKEN` for the `gh`
# commands that post the review, so the review posts under the bot identity
# rather than your own account.
#
#   GH_TOKEN="$(.../mint-token.sh <owner>)" gh pr review <n> --repo <owner>/<repo> ...
#
# The optional first argument is the target repo's owner (org or personal login;
# `owner/repo` is also accepted and trimmed). The bot may be installed on several
# accounts (an org and your personal account), so the token is scoped to the
# installation on that owner. With no argument it falls back to the first/only
# installation (fine for a single-account setup, e.g. the setup verify step).
#
# Credentials are written by the `reviewer-setup` skill into the config dir
# (default ~/.config/agent-reviewer): config.json + private-key.pem. The App
# private key never leaves this machine — this script signs a JWT locally and
# exchanges it with GitHub for an installation token.
set -euo pipefail

OWNER="${1:-}"; OWNER="${OWNER%%/*}"   # optional target repo owner; trim owner/repo -> owner

CONFIG_DIR="${REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-reviewer}"
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"   # expand a leading ~, matching bootstrap.py's expanduser()
CONFIG="$CONFIG_DIR/config.json"
PEM="$CONFIG_DIR/private-key.pem"

if [ ! -f "$CONFIG" ] || [ ! -f "$PEM" ]; then
  echo "reviewer bot is not set up (no credentials in $CONFIG_DIR)." >&2
  echo "Run the reviewer-setup skill first to create your reviewer App." >&2
  exit 1
fi
for cmd in jq openssl curl; do
  command -v "$cmd" >/dev/null || { echo "$cmd is required but not installed" >&2; exit 1; }
done

APP_ID=$(jq -r '.app_id // empty' "$CONFIG")
INSTALLATION_ID=$(jq -r '.installation_id // empty' "$CONFIG")
[ -n "$APP_ID" ] || { echo "app_id missing from $CONFIG" >&2; exit 1; }

# base64url with no padding, per JWT (RFC 7515).
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# App JWT: ~9-minute TTL, iat backdated 60s for clock skew (per GitHub docs).
now=$(date +%s)
header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$APP_ID" | b64url)
unsigned="$header.$payload"
signature=$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$PEM" -binary | b64url)
jwt="$unsigned.$signature"

gh_app_api() {
  curl -fsS \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

# Resolve the installation to mint against. With an owner, pick the installation
# on that account (the bot may be installed on an org and your personal account);
# without one, fall back to the first/only installation.
if [ -n "$OWNER" ]; then
  INSTALLATION_ID=$(gh_app_api https://api.github.com/app/installations \
    | jq -r --arg o "$OWNER" 'map(select(.account.login | ascii_downcase == ($o | ascii_downcase))) | .[0].id // empty')
  [ -n "$INSTALLATION_ID" ] || {
    echo "reviewer App is not installed on '$OWNER' — install it there (reviewer-setup covers this)" >&2
    exit 1
  }
elif [ -z "$INSTALLATION_ID" ]; then
  INSTALLATION_ID=$(gh_app_api https://api.github.com/app/installations | jq -r '.[0].id // empty')
  [ -n "$INSTALLATION_ID" ] || {
    echo "the reviewer App has no installations — install it first (reviewer-setup covers this)" >&2
    exit 1
  }
fi

gh_app_api -X POST \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" \
  | jq -r '.token'
