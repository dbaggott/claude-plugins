# shellcheck shell=bash
# Where a role's data and configuration live, shared by `as-role.sh` and its
# GitHub backend `mint-token.sh`. Source it; it defines functions only.
#
# A role is a directory `roles/<role>/` beside `scripts/`, holding the role's
# `permissions.json`. Nothing here names a role: every caller loops over or is
# handed one.

ROLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES_DIR="$(cd "$ROLE_LIB_DIR/.." && pwd)/roles"

# Names are lowercase words joined by hyphens, which keeps the derived
# environment-variable prefix and the config path free of anything a shell or a
# path would read specially.
role_valid() {  # <role>
  [[ "$1" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] && [ -r "$ROLES_DIR/$1/permissions.json" ]
}

role_names() {
  local d
  for d in "$ROLES_DIR"/*/; do
    d="${d%/}"; d="${d##*/}"
    role_valid "$d" && printf '%s\n' "$d"
  done
}

role_perms_file() { printf '%s\n' "$ROLES_DIR/$1/permissions.json"; }

# DNBG_<ROLE>_ — `review-bot` becomes DNBG_REVIEW_BOT_.
role_env_prefix() {
  local up; up=$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')
  printf 'DNBG_%s_\n' "$up"
}

role_env() {  # <role> <field> — the value of DNBG_<ROLE>_<field>, or empty
  local var; var="$(role_env_prefix "$1")$2"
  printf '%s' "${!var:-}"
}

role_config_dir() {  # <role>
  local dir; dir=$(role_env "$1" CONFIG_DIR)
  [ -n "$dir" ] || dir="${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/$1"
  printf '%s\n' "${dir/#\~/$HOME}"   # a leading ~, as bootstrap.py's expanduser() reads it
}

# operator or refuse; absent is refuse. Anything else is a defect in the role's
# data, reported rather than read as either.
role_fallback() {  # <role>
  local p; p=$(jq -r '.fallback // "refuse"' "$(role_perms_file "$1")" 2>/dev/null) || return 1
  case "$p" in operator|refuse) printf '%s\n' "$p" ;; *) return 1 ;; esac
}

# What a write script's OK line ends with after a call through the resolver,
# from the resolver's stderr line `as-role.sh: result=OK as=<login>
# fallback=<…>`: ` as=<login>`, plus ` fallback=unconfigured` when the role ran
# as the operator.
role_as_tail() {  # <line>
  local rest=" ${1#as-role.sh: result=OK} " v
  v="${rest#* as=}"
  printf ' as=%s' "${v%% *}"
  case "$rest" in *" fallback=none "*) ;; *) printf ' fallback=unconfigured' ;; esac
}

# The bot login a role acts under on <repo>, from the resolver's login answer;
# nothing when the role has no bot there, a fallback to the operator included,
# so a caller filtering on it never mistakes the operator for the bot.
role_bot_login() {  # <role> <repo>
  "$ROLE_LIB_DIR/as-role.sh" --login "$1" "$2" 2>/dev/null \
    | sed -n 's/^result=OK login=\([^ ]*\) fallback=none$/\1/p'
}

# The login a role acts under on <repo> in either tier: its bot's, or the
# operator's own when the role falls back. When the resolver refuses, nothing on
# stdout, and its result line and reason on stderr.
role_login() {  # <role> <repo>
  local out; out=$("$ROLE_LIB_DIR/as-role.sh" --login "$1" "$2")
  case "$out" in
    "result=OK login="*) out="${out#result=OK login=}"; printf '%s\n' "${out%% *}" ;;
    *) printf 'as-role.sh: %s\n' "$out" >&2 ;;
  esac
}
