# shellcheck shell=bash
# Where a role's data and configuration live, shared by `as-role.sh` and its
# GitHub backend `mint-token.sh`. Source it; it defines functions only.
#
# A role is a directory `roles/<role>/` beside `scripts/`, holding the role's
# `permissions.json`. Nothing here names a role: every caller loops over or is
# handed one.

ROLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/roles"

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
