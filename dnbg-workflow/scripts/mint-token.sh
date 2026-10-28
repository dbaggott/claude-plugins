#!/usr/bin/env bash
# The GitHub backend of `as-role.sh`: mint a short-lived installation token for
# a role's GitHub App and print it to stdout. Call `as-role.sh`, not this —
# it decides whether the role is configured at all, and runs the command with
# the token in place so the token never passes through a caller.
#
#   mint-token.sh <role> [<owner>]
#
# `<owner>` is the target repo's owner (org or personal login; `owner/repo` is
# also accepted and trimmed). The App may be installed on several accounts, so
# the token is scoped to the installation on that owner. With no owner it falls
# back to the first/only installation.
#
# Credentials are written by the `reviewer-setup` skill into the role's config
# dir (default ~/.config/dnbg/<role>, or DNBG_<ROLE>_CONFIG_DIR): config.json +
# private-key.pem. The App private key never leaves this machine — this script
# signs a JWT locally and exchanges it with GitHub for an installation token.
# `<ROLE>` below is the role name upper-cased, hyphens as underscores.
#
# ## Where the key comes from
#
# Three sources, tried in this order. The first that yields a key wins:
#
#   1. DNBG_<ROLE>_PRIVATE_KEY          the PEM itself, in the environment
#   2. DNBG_<ROLE>_PRIVATE_KEY_COMMAND  a command whose stdout is the PEM
#      (or `private_key_command` in config.json)
#   3. $CONFIG_DIR/private-key.pem      the plaintext file bootstrap.py writes
#
# Two more variables stand in for config.json fields, so a headless run needs no
# config file at all. Both fall back to config.json when it exists:
#
#   DNBG_<ROLE>_APP_ID           required — without it there is no JWT to sign
#   DNBG_<ROLE>_INSTALLATION_ID  optional — skips the /app/installations
#                                lookup; otherwise it is resolved from <owner>
#
# (2) is the single hook that reaches every secret manager without this project
# knowing any of them exist — `op read`, `pass show`, `security find-generic-
# password -w`, `secret-tool lookup`, `vault kv get`, `sops -d`. `git`'s
# `credential.helper` is the precedent.
#
# ⚠️ THE COMMAND IS READ ONLY FROM USER CONFIG OR THE ENVIRONMENT, NEVER FROM A
# REPOSITORY, and that is the property the whole feature's safety rests on. It is
# safe because someone who can write `~/.config/dnbg/<role>` can already write
# `~/.zshrc` or swap the PEM outright — so the command grants no capability they
# lacked. That argument evaporates the instant a repo can supply the value, which
# is the class of bug `credential.helper` has been bitten by repeatedly. Nothing
# here reads a config file from the working directory, and a test asserts it.
set -euo pipefail

# shellcheck source=./lib-role.sh
. "$(dirname "$0")/lib-role.sh"

ROLE="${1:-}"
role_valid "$ROLE" || { echo "usage: mint-token.sh <role> [<owner>] — '$ROLE' is not a role under $ROLES_DIR" >&2; exit 1; }
OWNER="${2:-}"; OWNER="${OWNER%%/*}"   # optional target repo owner; trim owner/repo -> owner
ENV_PREFIX="$(role_env_prefix "$ROLE")"

CONFIG_DIR="$(role_config_dir "$ROLE")"
CONFIG="$CONFIG_DIR/config.json"
PEM="$CONFIG_DIR/private-key.pem"

for cmd in jq openssl curl; do
  command -v "$cmd" >/dev/null || { echo "$cmd is required but not installed" >&2; exit 1; }
done

# Refuse a credential anyone but the owner can rewrite, the way ssh refuses an
# over-permissive private key. A 0600 PEM in a 0777 directory is not protected:
# the file cannot be read, but it can be REPLACED, and this script would then
# sign a JWT with the attacker's key and hand back a real token for the bot.
#
# `find -perm` rather than `stat`: the format flags differ between BSD and GNU
# (`stat -f '%Lp'` vs `stat -c '%a'`), and this comparison does not need the
# number — only whether either write bit is set.
#
# `-L`, and it is load-bearing in both directions. Without it `find` stats the
# symlink rather than its target, and a symlink's own mode is `0777` on Linux
# unconditionally (`symlink()` ignores umask). So every config dir or PEM that a
# dotfile manager — stow, chezmoi, dotbot — has linked into `~/.config` would be
# refused however locked-down the real directory is, on all three routes, and the
# remedy this prints could not clear it: `chmod` follows the link, so `chmod go-w`
# would re-chmod the already-correct target and leave the link at `0777` forever.
# It is also the weaker check: without `-L`, a link pointing at a genuinely
# world-writable directory is let straight through. Both verified by hand.
refuse_if_writable() {  # <path> <what>
  [ -e "$1" ] || return 0
  [ -n "$(find -L "$1" -maxdepth 0 \( -perm -g+w -o -perm -o+w \) 2>/dev/null)" ] || return 0
  echo "refusing to use $2: $1 is group- or world-writable." >&2
  echo "A credential anyone can replace is not a credential. Fix with: chmod go-w '$1'" >&2
  exit 1
}

# The env-var route must stand alone — that is the headless/CI case, where there
# is no config dir at all. So app_id has its own variable: it lives in
# config.json on a workstation, and without it there is no JWT to sign.
APP_ID="$(role_env "$ROLE" APP_ID)"
INSTALLATION_ID="$(role_env "$ROLE" INSTALLATION_ID)"
KEY_COMMAND="$(role_env "$ROLE" PRIVATE_KEY_COMMAND)"
KEY_COMMAND_FROM="${ENV_PREFIX}PRIVATE_KEY_COMMAND"
ENV_KEY="$(role_env "$ROLE" PRIVATE_KEY)"

if [ -f "$CONFIG" ]; then
  refuse_if_writable "$CONFIG_DIR" "the $ROLE config directory"
  refuse_if_writable "$CONFIG" "the $ROLE config"
  [ -n "$APP_ID" ] || APP_ID=$(jq -r '.app_id // empty' "$CONFIG")
  [ -n "$INSTALLATION_ID" ] || INSTALLATION_ID=$(jq -r '.installation_id // empty' "$CONFIG")
  [ -n "$KEY_COMMAND" ] || {
    KEY_COMMAND=$(jq -r '.private_key_command // empty' "$CONFIG")
    KEY_COMMAND_FROM="private_key_command in $CONFIG"
  }
fi

if [ -z "$APP_ID" ]; then
  echo "the $ROLE App is not set up: no app_id." >&2
  echo "Run the reviewer-setup skill, or set ${ENV_PREFIX}APP_ID for a headless run." >&2
  exit 1
fi

# Resolve the key into memory, in the documented order. `KEY` holds the PEM from
# here on and is never written anywhere.
KEY=""
KEY_SOURCE=""
if [ -n "$ENV_KEY" ]; then
  KEY="$ENV_KEY"; KEY_SOURCE="${ENV_PREFIX}PRIVATE_KEY"
elif [ -n "$KEY_COMMAND" ]; then
  # `sh -c` so the configured value can be an ordinary command line with flags
  # and pipes, which is what every manager's documented invocation looks like.
  # Its failures never echo it: it may carry a vault token as an argument, and
  # this stderr reaches the agent's transcript through as-role.sh.
  KEY=$(sh -c "$KEY_COMMAND") || {
    echo "the $ROLE App's private key command ($KEY_COMMAND_FROM) failed." >&2
    exit 1
  }
  # Reported here rather than left to the not-set-up message below. The `elif`
  # has already committed to this route, so falling through would name the PEM
  # file as something that was tried when it never was — pointing at the wrong
  # thing entirely. A manager that exits 0 with no output (wrong item name, a
  # vault that needs unlocking) is the likely way to land here.
  [ -n "$KEY" ] || {
    echo "the $ROLE App's private key command ($KEY_COMMAND_FROM) produced no output." >&2
    echo "It exited 0 but printed nothing — check the item name, and that any" >&2
    echo "vault or keychain it reads is unlocked." >&2
    exit 1
  }
  KEY_SOURCE="private key command"
elif [ -f "$PEM" ]; then
  refuse_if_writable "$CONFIG_DIR" "the $ROLE config directory"
  refuse_if_writable "$PEM" "the $ROLE private key"
  # The path, not the contents. This route's key is already a file on this
  # disk, at this mode — so reading it into memory and piping it back to openssl
  # protects nothing, and would make the *default* setup depend on /dev/fd for no
  # gain. Handing openssl the path it already had keeps this route working
  # anywhere openssl runs, which is what it did before any of this.
  KEY_PATH="$PEM"; KEY_SOURCE="$PEM"
fi

if [ -z "$KEY" ] && [ -z "${KEY_PATH:-}" ]; then
  echo "the $ROLE App is not set up (no private key)." >&2
  echo "Tried: ${ENV_PREFIX}PRIVATE_KEY, a key command, then $PEM." >&2
  echo "Run the reviewer-setup skill first to create your $ROLE App." >&2
  exit 1
fi

# ⚠️ A KEY RESOLVED INTO MEMORY REACHES openssl THROUGH A PIPE, NEVER A TEMP FILE.
# `openssl dgst -sign` takes a path, so the obvious implementation writes one and
# removes it in a trap — but a trap does not run on SIGKILL, and there is a window
# between `mktemp` and installing it, so "no key on disk" would hold only most of
# the time. Process substitution gives openssl `/dev/fd/N`, which is the pipe:
# nothing to strand, on any signal.
#
# This matters only for the env and command routes. Someone using `op read` has
# decided the key is not to sit at rest on this disk, and quietly writing it to
# TMPDIR on every mint would reverse that decision without telling them. The file
# route is exempt above — its key is already on disk, so it hands over the path.
#
# Verified signing from a pipe under OpenSSL 3.6.2 and LibreSSL 3.3.6; CI covers
# Linux. Deliberately NOT falling back to a temp file if this fails: openssl
# exits 1 both for "cannot open the key" and "the key is malformed", with
# different wording per implementation, so a fallback cannot tell those apart —
# it would fire on a bad key and write it to disk before failing anyway, dropping
# the guarantee at exactly the moment something is already wrong. Fail loudly.
if [ -z "${KEY_PATH:-}" ] && ! { [ -r /dev/fd/3 ]; } 3</dev/null; then
  echo "/dev/fd is not usable on this system, so a key held in memory cannot reach" >&2
  echo "openssl without being written to disk. Refusing rather than weakening the" >&2
  echo "key handling — use the private-key.pem file route, which needs no /dev/fd." >&2
  exit 1
fi

# base64url with no padding, per JWT (RFC 7515).
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# App JWT: ~9-minute TTL, iat backdated 60s for clock skew (per GitHub docs).
now=$(date +%s)
header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$APP_ID" | b64url)
unsigned="$header.$payload"
if [ -n "${KEY_PATH:-}" ]; then
  signature=$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$KEY_PATH" -binary | b64url)
else
  signature=$(printf '%s' "$unsigned" \
    | openssl dgst -sha256 -sign <(printf '%s\n' "$KEY") -binary | b64url)
fi || {
  echo "signing the App JWT failed — the key from $KEY_SOURCE is not a usable RSA private key" >&2
  exit 1
}
jwt="$unsigned.$signature"

# The JWT reaches curl through a pipe, not its argv: other users can read a
# running process's arguments (`ps`, `/proc/*/cmdline`), and the JWT can mint a
# token on every installation of the App. curl reads `-H @<file>` as a file of
# headers, one per line.
gh_app_api() {
  curl -fsS \
    -H @<(printf 'Authorization: Bearer %s\n' "$jwt") \
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
    echo "the $ROLE App is not installed on '$OWNER' — install it there (reviewer-setup covers this)" >&2
    exit 1
  }
elif [ -z "$INSTALLATION_ID" ]; then
  INSTALLATION_ID=$(gh_app_api https://api.github.com/app/installations | jq -r '.[0].id // empty')
  [ -n "$INSTALLATION_ID" ] || {
    echo "the $ROLE App has no installations — install it first (reviewer-setup covers this)" >&2
    exit 1
  }
fi

# The mint response carries the granted permissions alongside the token, so
# checking them here costs no request.
MINTED=$(gh_app_api -X POST \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens")

PERMS_FILE="$(role_perms_file "$ROLE")"
if [ -r "$PERMS_FILE" ]; then
  SHORTFALL=$(printf '%s' "$MINTED" | jq -r --slurpfile spec "$PERMS_FILE" '
    {"read":1, "write":2, "admin":3} as $rank
    | ($spec[0]) as $s
    | (.permissions // {}) as $got
    | [ $s.required | to_entries[]
        | select(($rank[$got[.key] // ""] // 0) < ($rank[.value] // 0))
        | "  \(.key): need \(.value), " +
          (if $got[.key] then "have \($got[.key])" else "not granted" end) +
          "\n      without it, \($s.consequence[.key] // "a capability is lost")" ]
    | join("\n")')

  if [ -n "$SHORTFALL" ]; then
    SLUG=$(jq -r '.slug // "<your-app>"' "$CONFIG" 2>/dev/null || echo "<your-app>")
    cat >&2 <<EOM
The $ROLE App is missing a permission it needs:

$SHORTFALL

  Only the App owner can grant this, so raise it with the operator and ask them to:
    1. https://github.com/settings/apps/$SLUG/permissions
       set the permission above, then Save.
    2. https://github.com/settings/installations
       accept the pending request on each installation — until then the grant
       is not in effect and nothing changes.

  Then re-run whatever you were doing. This message appears only while something
  is missing.
EOM
  fi
fi

printf '%s' "$MINTED" | jq -r '.token'
