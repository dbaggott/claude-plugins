#!/usr/bin/env bash
# The role resolver: the one place that knows how an agent role — reviewer,
# author, orchestrator — acts on a forge. Every other script and skill asks it.
#
#   as-role.sh <role> <repo> -- <cmd…>   run <cmd…> with the role's credential
#   as-role.sh --login <role> <repo>     the login the role acts under
#   as-role.sh --operator <repo>         the operator's own login
#   as-role.sh --fallbacks               the roles that would act as the operator
#
# <repo> is `host/namespace/…/name`, a remote URL (https://, ssh://, or
# `git@host:namespace/name`), or `owner/name`, which is short for
# `github.com/owner/name`. A bare owner is refused: a namespace alone does not
# say which forge, and on GitLab namespaces nest.
#
# ## Credential
#
# Runs <cmd…> by exec, with the credential where the forge's tool reads it
# (`GH_TOKEN` on GitHub), so mint and use are one process and the token reaches
# no file, git config, remote URL or output. Before the exec it writes one line
# to stderr, leaving stdout to the command:
#   as-role.sh: result=OK as=<login|unknown> fallback=<none|unconfigured>
# When the resolver itself fails, the command does not run, and it exits 125
# after writing to stderr:
#   as-role.sh: result=ERROR reason=<reason>
# followed by what to do about it. The command may exit 125 itself, so that
# stderr line, not the exit status, is what says the resolver refused.
#
# ## Login, operator, fallbacks
#
# One line on stdout, then exit 0:
#   result=OK login=<login> fallback=<none|unconfigured>   # --login, --operator
#   result=OK roles=<role,…|none>                          # --fallbacks
#   result=ERROR reason=<reason>
#
# On GitHub a role's login is its App slug; GitHub spells the bot's user
# `<slug>[bot]` in REST and `<slug>` in GraphQL, and consumers add the suffix
# where they need it. A configured role with no known login is `no-login`,
# never the operator's. `--operator` reads the operator's login under the
# operator's own forge auth, with no role credential in place. `--fallbacks`
# reads configuration presence only, through the same test the other calls
# use, and makes no network call, for the SessionStart notice. It takes no
# repo, and answers for GitHub, the only backend.
#
# ## Fallback
#
# A role with no configuration for the forge acts as the operator only if its
# `roles/<role>/permissions.json` says `"fallback": "operator"`; otherwise the
# call fails with `not-configured`. A role that IS configured and whose
# credential fails is an error, never the operator: a silent drop to the
# operator's login is exactly what per-role identities exist to prevent. Any
# two configured roles resolving to one App fail every call with
# `shared-identity`; roles falling back may share the operator.
#
# Reasons: bad-args, bad-repo, unsupported-forge, unknown-role, bad-role-data,
# not-configured, shared-identity, no-login, credential, operator-auth.
#
# Only GitHub is implemented. A backend is the four `<forge>_*` functions
# below, chosen at the single `case` in `forge_of`.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib-role.sh
. "$HERE/lib-role.sh"

MODE=""   # set before fail() can run, so it knows which channel to use

fail() {  # <reason> [<detail>]
  if [ "$MODE" = credential ]; then
    echo "as-role.sh: result=ERROR reason=$1" >&2
    [ -z "${2:-}" ] || printf '%s\n' "$2" >&2
    exit 125
  fi
  echo "result=ERROR reason=$1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" >&2
  exit 0
}

# --- repo spec ---------------------------------------------------------------

HOST=""; REPO_PATH=""
parse_repo() {  # <repo> -> HOST, REPO_PATH
  local spec="$1" rest
  while [[ "$spec" == */ ]]; do spec="${spec%/}"; done
  case "$spec" in
    https://*|http://*) rest="${spec#*://}"; HOST="${rest%%/*}"; REPO_PATH="${rest#*/}" ;;
    ssh://*) rest="${spec#ssh://}"; rest="${rest#*@}"; HOST="${rest%%/*}"; HOST="${HOST%%:*}"
             REPO_PATH="${rest#*/}" ;;
    *@*:*) rest="${spec#*@}"; HOST="${rest%%:*}"; REPO_PATH="${rest#*:}" ;;
    */*/*) HOST="${spec%%/*}"; REPO_PATH="${spec#*/}" ;;
    */*) HOST=github.com; REPO_PATH="$spec" ;;
    *) fail bad-repo "a repo is host/namespace/name, a remote URL, or owner/name — not a bare owner: '$spec'" ;;
  esac
  HOST="${HOST#*@}"; HOST=$(printf '%s' "$HOST" | tr '[:upper:]' '[:lower:]')
  REPO_PATH="${REPO_PATH%/}"; REPO_PATH="${REPO_PATH%.git}"
  [ -n "$HOST" ] && [ "$HOST" != "$REPO_PATH" ] || fail bad-repo "no host in '$spec'"
  local seg segs
  IFS=/ read -ra segs <<<"$REPO_PATH"
  [ "${#segs[@]}" -ge 2 ] || fail bad-repo "'$spec' names no namespace and repository"
  for seg in "${segs[@]}"; do
    case "$seg" in ''|.|..) fail bad-repo "'$spec' has an empty or dot segment" ;; esac
  done
}

FORGE=""
forge_of() {  # HOST -> FORGE
  case "$HOST" in
    github.com) FORGE=github
      [[ "$REPO_PATH" != */*/* ]] || fail bad-repo "a GitHub repo is owner/name, not '$REPO_PATH'" ;;
    *) fail unsupported-forge "no backend for '$HOST' yet; only github.com is implemented" ;;
  esac
}

# --- GitHub backend ----------------------------------------------------------
#
# A role is configured on GitHub when any of its App's settings exist: the
# config.json bootstrap.py writes, or the DNBG_<ROLE>_* variables a headless
# run uses instead. Partial configuration counts as configured, so it reaches
# the mint and fails there with the mint's own message, rather than falling
# back past a half-finished setup.

github_configured() {  # <role>
  [ -f "$(role_config_dir "$1")/config.json" ] && return 0
  local f
  for f in APP_ID PRIVATE_KEY PRIVATE_KEY_COMMAND; do
    [ -n "$(role_env "$1" "$f")" ] && return 0
  done
  return 1
}

github_config_field() {  # <role> <env-field> <json-field>
  local v; v=$(role_env "$1" "$2")
  if [ -z "$v" ]; then
    local conf; conf="$(role_config_dir "$1")/config.json"
    [ -f "$conf" ] && v=$(jq -r --arg k "$3" '.[$k] // empty' "$conf" 2>/dev/null || true)
  fi
  printf '%s' "$v"
}

# What makes two roles the same actor: the App id where known, else its slug.
github_identity() {  # <role>
  local id; id=$(github_config_field "$1" APP_ID app_id)
  if [ -n "$id" ]; then printf 'app:%s' "$id"; return; fi
  id=$(github_config_field "$1" SLUG slug)
  [ -z "$id" ] || printf 'slug:%s' "$id"
}

github_login() {  # <role>
  github_config_field "$1" SLUG slug
}

github_operator() {
  env -u GH_TOKEN -u GITHUB_TOKEN gh api user --jq .login </dev/null 2>/dev/null
}

github_exec() {  # <role> <cmd…>
  local role="$1"; shift
  local owner="${REPO_PATH%%/*}" token
  # stdin stays the command's: a key command must not consume what was piped in
  # for it.
  token=$(bash "$HERE/mint-token.sh" "$role" "$owner" </dev/null) \
    || fail credential "the $role App's credential failed (above); not running as anyone else."
  [ -n "$token" ] || fail credential "the $role App's mint returned no token; not running as anyone else."
  export GH_TOKEN="$token"
  unset GITHUB_TOKEN token
  exec "$@"
}

github_exec_operator() {  # <cmd…>
  unset GH_TOKEN GITHUB_TOKEN
  exec "$@"
}

# --- forge-neutral -----------------------------------------------------------

check_role() {  # <role>
  role_valid "$1" || fail unknown-role "'$1' is not a role: no $ROLES_DIR/$1/permissions.json"
  role_fallback "$1" >/dev/null \
    || fail bad-role-data "$ROLES_DIR/$1/permissions.json: \"fallback\" must be \"operator\" or \"refuse\""
}

# Fails when two configured roles resolve to one identity. Local reads only.
check_distinct() {
  local role id seen="" other
  while IFS= read -r role; do
    "${FORGE}_configured" "$role" || continue
    id=$("${FORGE}_identity" "$role")
    [ -n "$id" ] || continue
    other=$(printf '%s' "$seen" | awk -F'\t' -v id="$id" '$2 == id { print $1; exit }')
    [ -z "$other" ] || fail shared-identity \
      "the $other and $role roles are configured with one App ($id); each role needs its own."
    seen="$seen$role	$id
"
  done < <(role_names)
}

# configured -> bot; unconfigured and allowed -> operator; else fail.
TIER=""
resolve_tier() {  # <role>
  if "${FORGE}_configured" "$1"; then TIER=bot; return; fi
  [ "$(role_fallback "$1")" = operator ] && { TIER=operator; return; }
  fail not-configured "the $1 role has no App set up and does not fall back to your account. Run the reviewer-setup skill to create it."
}

OPERATOR=""
read_operator() {  # -> OPERATOR; in this shell, so a failure exits the script
  OPERATOR=$("${FORGE}_operator") || OPERATOR=""
  [ -n "$OPERATOR" ] || fail operator-auth "could not read your own login under your own forge auth (is \`gh auth status\` healthy?)"
}

case "${1:-}" in
  --login)
    MODE=answer; [ "$#" -eq 3 ] || fail bad-args
    check_role "$2"; parse_repo "$3"; forge_of; check_distinct; resolve_tier "$2"
    if [ "$TIER" = bot ]; then
      LOGIN=$("${FORGE}_login" "$2")
      [ -n "$LOGIN" ] || fail no-login "the $2 App is configured but its login is unknown: set slug in its config.json, or $(role_env_prefix "$2")SLUG."
      echo "result=OK login=$LOGIN fallback=none"
    else
      read_operator
      echo "result=OK login=$OPERATOR fallback=unconfigured"
    fi ;;
  --operator)
    MODE=answer; [ "$#" -eq 2 ] || fail bad-args
    parse_repo "$2"; forge_of; read_operator
    echo "result=OK login=$OPERATOR fallback=none" ;;
  --fallbacks)
    MODE=answer; [ "$#" -eq 1 ] || fail bad-args
    FORGE=github; check_distinct
    LIST=""
    while IFS= read -r role; do
      check_role "$role"
      github_configured "$role" && continue
      [ "$(role_fallback "$role")" = operator ] && LIST="${LIST:+$LIST,}$role"
    done < <(role_names)
    echo "result=OK roles=${LIST:-none}" ;;
  -*) MODE=answer; fail bad-args ;;
  *)
    MODE=credential
    [ "$#" -ge 4 ] && [ "$3" = -- ] || fail bad-args "usage: as-role.sh <role> <repo> -- <cmd…>"
    ROLE="$1"; check_role "$ROLE"; parse_repo "$2"; forge_of; shift 3
    check_distinct; resolve_tier "$ROLE"
    if [ "$TIER" = bot ]; then
      LOGIN=$("${FORGE}_login" "$ROLE")
      echo "as-role.sh: result=OK as=${LOGIN:-unknown} fallback=none" >&2
      "${FORGE}_exec" "$ROLE" "$@"
    else
      read_operator
      echo "as-role.sh: result=OK as=$OPERATOR fallback=unconfigured" >&2
      "${FORGE}_exec_operator" "$@"
    fi ;;
esac
